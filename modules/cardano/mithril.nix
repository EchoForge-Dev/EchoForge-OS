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
  bp = cfg.node.mithril.blockProducer;

  # 仅对落在 sops-nix 解密挂载点下的默认路径自动声明 secrets 条目；
  # 用户改用其他路径时自行负责该文件的存在与属主
  secretsRoot = "/run/secrets/";
  bpSecretNames = map (lib.removePrefix secretsRoot) (
    builtins.filter (lib.hasPrefix secretsRoot) [
      bp.kesKeyFile
      bp.vrfKeyFile
      bp.opCertFile
    ]
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
  config = lib.mkIf cfg.node.mithril.enable {
    assertions = [
      {
        assertion = bp.enable -> builtins.pathExists ../../secrets/secrets.yaml;
        message = ''
          echoforge.node.mithril.blockProducer 需要 secrets/secrets.yaml
          （sops-nix Age 加密）提供 pool/kes.skey、pool/vrf.skey、pool/node.cert，
          见 secrets/README.md。
        '';
      }
    ];

    # KES/VRF/OpCert 经 sops-nix 解密到 /run/secrets/pool/，属主限定 cardano 用户
    sops.secrets = lib.mkIf bp.enable (
      lib.genAttrs bpSecretNames (_: {
        owner = "cardano";
        group = "cardano";
        mode = "0400";
      })
    );

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
