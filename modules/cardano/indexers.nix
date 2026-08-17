# 本地索引层：Ogmios (WebSocket 桥) + Kupo (UTxO 索引)
# 跟随 ef-cli 拉起的任意节点（统一 socket：/run/echoforge/node.socket）
# 严格网络隔离：仅监听 echoforge.node.hostAddr（默认 127.0.0.1），防火墙不放行
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  brand = import ../common/brand.nix;
in
{
  config = lib.mkIf cfg.node.indexers.enable {
    systemd.services.ef-ogmios = {
      description = "EchoForge Ogmios bridge (localhost only)";
      documentation = brand.unitDocumentation;
      # 仅由 ef-cli 拉起
      serviceConfig = {
        Type = "simple";
        User = "cardano";
        Group = "cardano";
        RuntimeDirectory = "echoforge";
        RuntimeDirectoryPreserve = true;
        ExecStart = ''
          ${pkgs.ogmios}/bin/ogmios \
            --node-socket /run/echoforge/node.socket \
            --node-config /run/echoforge/node-config.json \
            --host ${cfg.node.hostAddr} \
            --port 1337
        '';
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    systemd.services.ef-kupo = {
      description = "EchoForge Kupo indexer (localhost only)";
      documentation = brand.unitDocumentation;
      serviceConfig = {
        Type = "simple";
        User = "cardano";
        Group = "cardano";
        StateDirectory = "echoforge/kupo";
        RuntimeDirectory = "echoforge";
        RuntimeDirectoryPreserve = true;
        ExecStart = ''
          ${pkgs.kupo}/bin/kupo \
            --node-socket /run/echoforge/node.socket \
            --node-config /run/echoforge/node-config.json \
            --host ${cfg.node.hostAddr} \
            --port 1442 \
            --workdir /var/lib/echoforge/kupo \
            --match "*" \
            --since origin
        '';
        Restart = "on-failure";
        RestartSec = 3;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
