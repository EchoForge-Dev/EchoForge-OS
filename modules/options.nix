# EchoForge 全局选项命名空间
{ config, lib, ... }:
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

    eggs.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        EchoForge 彩蛋层（系统层：机器身份 / 控制台调色板 / sudo 与包管理器提示 / GUI 附加项 / depin LED）。
        全部为静态文本或按需触发，无守护进程、无网络、无特权变化；生产机只拿到被动元数据。
        ef-cli 内建的彩蛋不受此开关影响。
      '';
    };

    node = {
      hostAddr = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          **索引层与 RPC 的监听地址**（Ogmios / Kupo，以及 devnet 私链节点）。
          安全规范默认锁定 127.0.0.1，common/security.nix 有构建期断言把关。

          注意：这里**不再**决定 mithril 全节点的 P2P 绑定地址 ——
          那是 node.mithril.p2pAddr。两者混用会造成一个很隐蔽的故障：
          把 P2P 绑到回环后，出站 connect 的源地址也是回环，
          去连任何公网对端都直接 EINVAL，节点零对端、永远停在快照结束处，
          而 syncProgress 仍显示 99%+，表面完全健康。
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
          type = lib.types.ints.u32;
          default = 42;
          example = 20260411; # 2026-04-11 —— EchoForge 成立日写成整数（仅示例；默认保持 42 以兼容 cardano-cli/yaci 的肌肉记忆）
          description = "devnet testnet magic（只在首次生成创世时生效；改动后需删除已有创世目录才会重建）。";
        };
      };

      mithril = {
        enable = lib.mkEnableOption "Mithril 快照引导的 preview/preprod/mainnet 节点单元（仅由 ef-cli 启动）";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3001;
          description = "节点 P2P 监听端口（中继节点需与拓扑中公布的端口一致）。";
        };

        p2pAddr = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = ''
            全节点的 P2P 绑定地址（cardano-node --host-addr）。

            默认 0.0.0.0，**这不等于对外暴露**：入站是否可达由防火墙决定，
            3001 不在 allowedTCPPorts 里外部就进不来（见 openFirewall）。
            而出站连接不受入站防火墙限制 —— 节点必须绑一个可路由地址
            才连得上对端，绑 127.0.0.1 会让所有出站 connect 返回 EINVAL。

            只有在多网卡机器上想把 P2P 限定到某张网卡时才需要改动。
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            在防火墙放行 `port`，让外部连得进来。中继节点必须开启；
            出块节点不应开启 —— 它只主动外连自有中继，入站应由
            networking.firewall.extraInputRules 按中继 IP 精确放行。

            这只管入站。节点绑哪个地址是 `p2pAddr`（默认 0.0.0.0 即可，
            不要改 `node.hostAddr` —— 那是索引层的监听地址）。
          '';
        };

        topology = {
          localRoots = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  address = lib.mkOption {
                    type = lib.types.str;
                    description = "自有节点的域名或 IP。";
                  };
                  port = lib.mkOption {
                    type = lib.types.port;
                    default = 3001;
                    description = "对端 P2P 端口。";
                  };
                };
              }
            );
            default = [ ];
            example = [
              {
                address = "relay-1.example.com";
                port = 3001;
              }
            ];
            description = ''
              自有节点（trustable local roots）。非空时生成私有 topology.json
              取代官方公共拓扑：出块节点填自己的中继，中继节点填出块节点与
              兄弟中继。留空则沿用官方公共拓扑（仅适合观察节点）。
            '';
          };

          bootstrapPeers = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.listOf (
                lib.types.submodule {
                  options = {
                    address = lib.mkOption { type = lib.types.str; };
                    port = lib.mkOption {
                      type = lib.types.port;
                      default = 3001;
                    };
                  };
                }
              )
            );
            default = null;
            description = ''
              P2P bootstrap peers。出块节点必须保持 null（不连公网发现），
              中继节点可填官方 environments/<network>/topology.json 中的条目。
              仅在 `topology.localRoots` 非空时生效。
            '';
          };

          useLedgerAfterSlot = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = ''
              从该 slot 起启用 ledger peers。null 时按角色取默认：
              出块节点 -1（永不使用，只连自有中继），中继节点 0。
              仅在 `topology.localRoots` 非空时生效。
            '';
          };
        };

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

      led.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          板载 ACT LED 映射节点状态（2 s 呼吸 = 运行，250 ms = Mithril 快照恢复中，
          mmc0 = 停止）。这是硬件特性而非 Profile 特性 —— 由硬件叠加层开启
          （见 profiles/depin-hw-rpi4.nix），x86 迷你主机上没有这块 LED。
        '';
      };
    };
  };
}
