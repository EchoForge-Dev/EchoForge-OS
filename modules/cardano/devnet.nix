# Local Devnet：~200MB 内存预算、秒级出块的单节点私有链
# 首次启动自动生成创世（cardano-cli conway genesis create-testnet-data）
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  brand = import ../common/brand.nix;

  devnetRun = pkgs.writeShellApplication {
    name = "ef-devnet-run";
    runtimeInputs = [
      pkgs.cardano-node-bin
      pkgs.jq # 改写创世时序参数、读 systemStart
      pkgs.coreutils # date -u -d：把 systemStart 换算成 Byron 的 POSIX 秒
    ];
    text = builtins.readFile ../../scripts/devnet-run.sh;
  };
in
{
  config = lib.mkIf cfg.node.devnet.enable {
    systemd.services.ef-devnet = {
      description = "EchoForge Local Devnet (single-node private Cardano chain)";
      documentation = brand.unitDocumentation;
      # 刻意没有 wantedBy —— 仅 ef-cli node start --mode devnet 可拉起
      environment = {
        EF_DEVNET_MAGIC = toString cfg.node.devnet.magic;
        EF_DEVNET_PORT = toString cfg.node.devnet.port;
        EF_HOST = cfg.node.hostAddr;
        # 节点配置模板取自发布件自带的 share/cardano/preview/，见 scripts/devnet-run.sh
        EF_NODE_SHARE = "${pkgs.cardano-node-bin}/share/cardano";
      };
      serviceConfig = {
        Type = "simple";
        User = "cardano";
        Group = "cardano";
        StateDirectory = "echoforge/devnet";
        RuntimeDirectory = "echoforge";
        RuntimeDirectoryPreserve = true;
        # 目录 0750 + socket 0770：cardano 组成员（运维用户）才连得上 node.socket，
        # 组权限止步于这个 socket，够不到 /run/secrets 下的密钥
        RuntimeDirectoryMode = "0750";
        UMask = "0007";
        ExecStart = "${devnetRun}/bin/ef-devnet-run";
        Restart = "on-failure";
        RestartSec = 3;
        # devnet 预算 ~200MB；硬顶 512M 防泄漏
        MemoryHigh = "256M";
        MemoryMax = "512M";
        # 沙箱化
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
