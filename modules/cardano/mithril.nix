# Mithril 快照引导的 preview / preprod / mainnet 节点
# ef-node@<network>：先经 ef-mithril-sync@<network> 秒级恢复数据库，再运行全节点
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  mithrilCfg = cfg.node.mithril;
  bp = mithrilCfg.blockProducer;
  top = mithrilCfg.topology;
  brand = import ../common/brand.nix;

  # 仅对落在 sops-nix 解密挂载点下的默认路径自动声明 secrets 条目；
  # 用户改用其他路径时自行负责该文件的存在与属主
  secretsRoot = "/run/secrets/";
  bpSecretSpecs = [
    {
      file = bp.kesKeyFile;
      mode = "0400";
    }
    {
      file = bp.vrfKeyFile;
      mode = "0400";
    }
    # 操作证书随区块头公开上链，本就不是秘密：放开组内可读，
    # 运维用户才跑得动 ef-cli pool status（query kes-period-info 要读它）
    {
      file = bp.opCertFile;
      mode = "0440";
    }
  ];
  bpSecrets = lib.listToAttrs (
    map (spec: {
      name = lib.removePrefix secretsRoot spec.file;
      value = {
        owner = "cardano";
        group = "cardano";
        inherit (spec) mode;
      };
    }) (builtins.filter (spec: lib.hasPrefix secretsRoot spec.file) bpSecretSpecs)
  );

  # 自有拓扑：localRoots 非空即接管 topology.json，不再拉官方公共拓扑。
  # 出块节点默认 useLedgerAfterSlot = -1（永不走 ledger peers，只连自有中继）。
  usePrivateTopology = top.localRoots != [ ];
  ledgerSlot =
    if top.useLedgerAfterSlot != null then
      top.useLedgerAfterSlot
    else if bp.enable then
      -1
    else
      0;
  accessPoints = map (peer: {
    inherit (peer) address port;
  });
  topologyFile = pkgs.writeText "ef-topology.json" (
    builtins.toJSON {
      localRoots = [
        {
          accessPoints = accessPoints top.localRoots;
          advertise = false;
          trustable = true;
          valency = builtins.length top.localRoots;
        }
      ];
      publicRoots = [ ];
      bootstrapPeers = if top.bootstrapPeers == null then null else accessPoints top.bootstrapPeers;
      useLedgerAfterSlot = ledgerSlot;
    }
  );

  mithrilSync = pkgs.writeShellApplication {
    name = "ef-mithril-sync";
    runtimeInputs = [
      pkgs.mithril-client-bin
      pkgs.curl
      pkgs.cacert
    ];
    text = builtins.readFile ../../scripts/mithril-sync.sh;
  };

  nodeRun = pkgs.writeShellApplication {
    name = "ef-node-run";
    runtimeInputs = [
      pkgs.cardano-node-bin
      pkgs.curl
      pkgs.cacert
    ];
    text = builtins.readFile ../../scripts/node-run.sh;
  };
in
{
  config = lib.mkIf mithrilCfg.enable {
    assertions = [
      {
        assertion = bp.enable -> builtins.pathExists ../../secrets/secrets.yaml;
        message = ''
          echoforge.node.mithril.blockProducer 需要 secrets/secrets.yaml
          （sops-nix Age 加密）提供 pool/kes.skey、pool/vrf.skey、pool/node.cert，
          见 secrets/README.md。
        '';
      }
      {
        assertion = mithrilCfg.openFirewall -> mithrilCfg.p2pAddr != "127.0.0.1";
        message = ''
          echoforge.node.mithril.openFirewall 放行了 P2P 端口，但
          echoforge.node.mithril.p2pAddr 仍是 127.0.0.1 —— 节点只绑回环，
          外部握手永远打不进来。中继节点请把 p2pAddr 设为可路由地址
          （通常是默认的 "0.0.0.0"）。
        '';
      }
    ];

    warnings =
      lib.optional (bp.enable && !usePrivateTopology) ''
        echoforge: 出块节点正在使用官方公共拓扑 —— 出块节点地址会暴露给全网。
        生产环境必须设置 echoforge.node.mithril.topology.localRoots 指向自有中继。
      ''
      ++ lib.optional (mithrilCfg.p2pAddr == "127.0.0.1") ''
        echoforge.node.mithril.p2pAddr = "127.0.0.1" —— 节点会把出站连接的源地址
        也绑到回环，去连任何公网对端都返回 EINVAL，结果是零对端、永远停在
        Mithril 快照结束的那个区块，而 syncProgress 仍显示 99%+，表面健康。
        除非你确知在做什么（例如完全离线的回放分析），否则请保持默认 0.0.0.0 ——
        它不会造成对外暴露，入站仍由防火墙把关。
      ''
      ++ lib.optional (bp.enable && mithrilCfg.openFirewall) ''
        echoforge: 出块节点开启了 openFirewall —— 出块节点不该对公网开放 P2P 端口。
        入站请改用 networking.firewall.extraInputRules 按自有中继 IP 精确放行。
      ''
      ++ lib.optional (bp.enable && top.bootstrapPeers != null) ''
        echoforge: 出块节点设置了 topology.bootstrapPeers —— 它会去连公网发现节点。
        出块节点应保持 null，只信任 localRoots 里的自有中继。
      '';

    # KES/VRF 私钥 0400；OpCert 0440（公开材料，运维用户需读取）
    # 全部经 sops-nix 解密到 /run/secrets/pool/，仅内存挂载
    sops.secrets = lib.mkIf bp.enable bpSecrets;

    networking.firewall.allowedTCPPorts = lib.mkIf mithrilCfg.openFirewall [ mithrilCfg.port ];

    # 快照同步（oneshot，可重入：数据库已存在时直接跳过）
    systemd.services."ef-mithril-sync@" = {
      description = "EchoForge Mithril snapshot sync (%i)";
      documentation = brand.unitDocumentation;
      serviceConfig = {
        Type = "oneshot";
        User = "cardano";
        Group = "cardano";
        StateDirectory = "echoforge/%i";
        ExecStart = "${mithrilSync}/bin/ef-mithril-sync %i";
        TimeoutStartSec = "6h"; # mainnet 快照较大
      };
    };

    # 全节点（模板单元，实例 = preview | preprod | mainnet）
    systemd.services."ef-node@" = {
      description = "EchoForge Cardano node (%i, mithril-bootstrapped)";
      documentation = brand.unitDocumentation;
      # 刻意没有 wantedBy —— 仅 ef-cli node start --mode mithril 可拉起

      # 系统层重建不得碰正在跑的节点。实测：即使单元文件逐字节未变，
      # nixos-rebuild switch 仍会重启它；而 Mithril 快照不含账本状态，
      # 节点追上链尖后还要再活满一个快照间隔（864s）才写下第一份 ledger 快照。
      # 在那之前被重启 = 从创世完整重放（preview 实测 46 分钟、内存峰值 3.3 GB，
      # mainnet 是数小时）。对出块节点就是无预警的长时间停机。
      # 代价：改了 node-run.sh 或节点版本后，运行中的实例仍跑旧代码，
      # 需要显式 `ef-cli node stop && ef-cli node start ...` 才生效 ——
      # 这正是「节点只由 ef-cli 掌控生命周期」该有的语义，停机窗口由人来选。
      restartIfChanged = false;
      stopIfChanged = false;
      environment = {
        # P2P 绑定地址 —— 不是 hostAddr。绑回环会让出站 connect 全部 EINVAL，
        # 节点零对端、停在快照结束处，而表面看起来完全健康（见 options.nix 说明）。
        EF_P2P_HOST = mithrilCfg.p2pAddr;
        EF_PORT = toString mithrilCfg.port;
        # 网络配置随二进制同包发布（share/cardano/<network>/），避免运行期抓
        # 「最新」配置与被钉住的节点版本漂移 —— 10.1.4 配 11.x 的配置会死在
        # Unknown config: "PrometheusSimple suffix ..."。顺带去掉启动时的网络依赖。
        EF_NODE_SHARE = "${pkgs.cardano-node-bin}/share/cardano";
      }
      # 自有拓扑：ef-node-run 见到 EF_TOPOLOGY 就不再拉官方公共 topology.json
      // lib.optionalAttrs usePrivateTopology {
        EF_TOPOLOGY = "${topologyFile}";
      }
      # 出块模式：ef-node-run 检测到三个变量齐备时追加 --shelley-* 出块参数
      // lib.optionalAttrs bp.enable {
        EF_KES_KEY = bp.kesKeyFile;
        EF_VRF_KEY = bp.vrfKeyFile;
        EF_OP_CERT = bp.opCertFile;
      };
      serviceConfig = {
        Type = "simple";
        User = "cardano";
        Group = "cardano";
        StateDirectory = "echoforge/%i";
        RuntimeDirectory = "echoforge";
        RuntimeDirectoryPreserve = true;
        # 目录 0750 + socket 0770：cardano 组成员（运维用户）才连得上
        # node.socket，组权限止步于这个 socket，够不到 /run/secrets 下的密钥
        RuntimeDirectoryMode = "0750";
        UMask = "0007";
        ExecStart = "${nodeRun}/bin/ef-node-run %i";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        LimitNOFILE = 65535;
      };
    };
  };
}
