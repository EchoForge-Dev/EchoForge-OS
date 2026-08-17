# 机器知道自己是 EchoForge：os-release VARIANT / hostnamectl / 世代标签 / 构建修订 /
# /etc/issue（登录前的球标）/ 无头机 motd / genesis.json / `efos` flake 别名。
# 全部是构建期字符串或静态文件：零运行时成本、零特权、零网络。
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.echoforge;
  brand = import ./brand.nix;
  edition =
    {
      desktop = "Desktop";
      dev = "Dev";
      spo = "SPO";
      depin = "DePIN Edge";
    }
    .${cfg.profile};
  chassis =
    {
      desktop = "desktop";
      dev = "desktop";
      spo = "server";
      depin = "embedded";
    }
    .${cfg.profile};
in
{
  config = lib.mkMerge [
    {
      # 溯源（非彩蛋）：nixos-version --configuration-revision → 本仓库 git rev（ef-cli version 的 REV 行）
      system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

      # EchoForge 的"创世文件"：公开事实，供 ef-* 单元 Documentation= 与好奇的读者
      environment.etc."echoforge/genesis.json".text = builtins.toJSON {
        name = "EchoForge OS";
        systemStart = "${brand.genesis}T00:00:00Z";
        genesisEpoch = brand.genesisEpoch;
        epochLength = brand.epochLength;
        slotLength = 1;
        motto = "${brand.motto} / ${brand.mottoZh}";
        profile = cfg.profile;
        variantId = "efos-${cfg.profile}";
        author = "Charles Tao";
        family = brand.family;
        home = brand.home;
      };
    }

    (lib.mkIf cfg.eggs.enable {
      # os-release：VARIANT="Dev" / VARIANT_ID=efos-dev；ID=nixos 不动（switch-to-configuration 等工具依赖）
      system.nixos.variantName = edition;
      system.nixos.variant_id = "efos-${cfg.profile}";
      # 世代标签：引导菜单 / nixos-rebuild list-generations 显示 efos-<profile>-<version>
      #（tags 会被排序 —— 只放一个 tag，避免 "dev-efos-…"）
      system.nixos.tags = [ "efos-${cfg.profile}" ];
      # SD 镜像形态是设备镜像：os-release IMAGE_ID
      system.image.id = lib.mkIf (cfg.profile == "depin") "echoforge-depin";

      # hostnamectl：Pretty hostname / Chassis / Deployment（只被 avahi/bluetooth 广播，均未启用）
      environment.etc."machine-info".text = ''
        PRETTY_HOSTNAME="EchoForge OS · ${edition}"
        CHASSIS=${chassis}
        DEPLOYMENT=${if cfg.profile == "dev" then "development" else "production"}
      '';

      # /etc/issue：登录前的球标（取代 NixOS 硬编码的绿色横幅；getty 模块用 mkDefault，这里直接覆盖）。
      # 桌面上藏在 Ctrl+Alt+F2 后面；RPi4 HDMI 上是第一眼 —— \4 打出本机 IPv4，无头 Pi 靠它被找到。
      environment.etc.issue.text = ''

        ${brand.markMedium}

           ECHOFORGE OS  .  \S{VARIANT}
           \n . \l . \4
           ALL FOR SIMPLE

      '';

      # 无头 Profile 的 motd（每次 SSH 都会打印 → 3 行、无艺术字）
      users.motd = lib.mkIf (!cfg.gui.enable) ''
        EchoForge OS · ${config.networking.hostName} · ${cfg.profile}
          node : ef-cli node status     system : ef-cli profile switch ${cfg.profile}
          ALL FOR SIMPLE · est. ${brand.genesis}
      '';

      # `nix run efos#ef-cli` / `nix flake metadata efos` —— 纯别名，只在显式引用时才联网
      nix.registry.efos.to = {
        type = "github";
        owner = "EchoForge-Dev";
        repo = "EchoForge-OS";
      };
    })
  ];
}
