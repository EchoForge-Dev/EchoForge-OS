# EchoForge 全局选项命名空间
{ lib, ... }:
{
  options.echoforge = {
    profile = lib.mkOption {
      type = lib.types.enum [
        "desktop"
        "dev"
        "spo"
        "depin"
      ];
      description = "当前激活的 EchoForge Profile。";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/echoforge";
      description = "节点数据库、devnet 创世与快照的持久化根目录。";
    };

    flakeRef = lib.mkOption {
      type = lib.types.str;
      default = "github:EchoForge-Dev/EchoForge-OS";
      description = "ef-cli profile switch 使用的 Flake 引用（可指向本地 checkout）。";
    };

    user.name = lib.mkOption {
      type = lib.types.str;
      default = "echo";
      description = "默认桌面 / 运维用户。";
    };

    user.sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAAC3... charles@mac" ];
      description = ''
        运维用户的 SSH 公钥（authorized_keys）。
        SSH 强制密钥登录 + 用户不可变，无头机器（spo/depin）
        不声明公钥就只剩控制台救援一条路 —— 装机前务必填上。
      '';
    };

    gui.enable = lib.mkEnableOption "EchoForge GUI（Hyprland + Waybar + EFDS 视觉规范）";

    node = {
      hostAddr = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          节点 / RPC 监听地址。安全规范默认锁定 127.0.0.1，
          仅 SPO 中继等明确场景可显式改为对外地址。
        '';
      };

      devnet = {
        enable = lib.mkEnableOption "按需拉起的 Local Devnet 单元（仅由 ef-cli 启动，绝不开机自启）";
        port = lib.mkOption {
          type = lib.types.port;
          default = 6000;
          description = "devnet cardano-node 监听端口。";
        };
        magic = lib.mkOption {
          type = lib.types.int;
          default = 42;
          description = "devnet testnet magic。";
        };
      };

      mithril = {
        enable = lib.mkEnableOption "Mithril 快照引导的 preview/preprod/mainnet 节点单元（仅由 ef-cli 启动）";

        blockProducer = {
          enable = lib.mkEnableOption ''
            SPO 出块节点模式：ef-node@ 单元追加 --shelley-kes-key /
            --shelley-vrf-key / --shelley-operational-certificate。
            密钥仅经 sops-nix 注入（secrets/secrets.yaml 的 pool/* 条目，
            解密挂载点 /run/secrets/pool/），绝不进入 Nix store
          '';

          kesKeyFile = lib.mkOption {
            type = lib.types.str;
            default = "/run/secrets/pool/kes.skey";
            description = "KES 签名密钥路径（运行期路径，非 Nix store）。";
          };

          vrfKeyFile = lib.mkOption {
            type = lib.types.str;
            default = "/run/secrets/pool/vrf.skey";
            description = "VRF 签名密钥路径（运行期路径，非 Nix store）。";
          };

          opCertFile = lib.mkOption {
            type = lib.types.str;
            default = "/run/secrets/pool/node.cert";
            description = "出块操作证书路径（运行期路径，非 Nix store）。";
          };
        };
      };

      indexers.enable = lib.mkEnableOption "Ogmios + Kupo 本地索引层（绑定 127.0.0.1，仅由 ef-cli 启动）";
    };
  };
}
