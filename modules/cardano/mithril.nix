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
        assertion = mithrilCfg.openFirewall -> cfg.node.hostAddr != "127.0.0.1";
        message = ''
          echoforge.node.mithril.openFirewall 放行了 P2P 端口，但
          echoforge.node.hostAddr 仍是 127.0.0.1 —— 节点只监听回环，
          外部握手永远打不进来。中继节点请一并把 hostAddr 设为对外地址
          （通常是 "0.0.0.0"）。
        '';
      }
    ];

    warnings =
      lib.optional (bp.enable && !usePrivateTopology) ''
        echoforge: 出块节点正在使用官方公共拓扑 —— 出块节点地址会暴露给全网。
        生产环境必须设置 echoforge.node.mithril.topology.localRoots 指向自有中继。
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

    users.users.cardano = {
      isSystemUser = true;
      group = "cardano";
    };
    users.groups.cardano = { };

    # 快照同步（oneshot，可重入：数据库已存在时直接跳过）
    systemd.services."ef-mithril-sync@" = {
      description = "EchoForge Mithril snapshot sync (%i)";
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
      # 刻意没有 wantedBy —— 仅 ef-cli node start --mode mithril 可拉起
      environment = {
        EF_HOST = cfg.node.hostAddr;
        EF_PORT = toString mithrilCfg.port;
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
