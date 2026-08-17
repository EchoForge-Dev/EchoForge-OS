# 动态节点引擎（CLAUDE.MD §3）
# 绝对禁止开机自启重型节点：以下所有单元均无 wantedBy，
# 只能由 ef-cli 按需拉起 / 释放。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  nodeEnabled = cfg.node.devnet.enable || cfg.node.mithril.enable;
in
{
  imports = [
    ./devnet.nix
    ./mithril.nix
    ./indexers.nix
  ];

  config = lib.mkIf nodeEnabled {
    # cardano-cli 与 cardano-node 同包：SPO 日常运维（query tip、
    # kes-period-info、注册证书、委托证书）全靠它，必须在 PATH 上，
    # 否则装完机敲的第一条命令就是 command not found。
    environment.systemPackages = [ pkgs.cardano-node-bin ];

    # cardano-cli 默认对接 ef-cli 拉起的节点 socket，免去每条命令带 --socket-path
    environment.variables.CARDANO_NODE_SOCKET_PATH = "/run/echoforge/node.socket";

    # 节点 socket 属主是 cardano 系统用户，目录 0750 / socket 0770（见各单元 UMask）。
    # 运维用户入组才能连接；组成员权限仅限该 socket，拿不到 /run/secrets 下的密钥。
    users.users.${cfg.user.name}.extraGroups = [ "cardano" ];
  };
}
