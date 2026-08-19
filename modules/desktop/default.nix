# EchoForge GUI 底座：Hyprland + Waybar + greetd，EFDS 字体体系
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;

  # tuigreet 大门（EFDS 单色主题、motto 问候、● 密码掩码；04-11 问候语换成 GENESIS DAY）。
  # 包装脚本以 greeter 用户在登录前运行：两次 date 后 exec 进 tuigreet，无网络、无 secrets。
  # 参数已逐一对照 tuigreet 0.9.1 的 man page（--greeting/--time-format/--theme/--asterisks-char/--greet-align/--width）。
  # 主题色是 ANSI 颜色名，落到 VT 调色板（modules/common/console.nix）上：white=#ffffff，darkgray=#404040。
  greeter = pkgs.writeShellScript "ef-greeter" ''
    d=$(${pkgs.coreutils}/bin/date +%m-%d)
    y=$(( $(${pkgs.coreutils}/bin/date +%Y) - 2026 ))
    g="ECHOFORGE OS · ALL FOR SIMPLE"
    if [ "$d" = 04-11 ]; then g="GENESIS DAY · YEAR $y · est. 2026-04-11"; fi
    exec ${pkgs.tuigreet}/bin/tuigreet \
      --time --time-format '%Y-%m-%d %H:%M' --remember \
      --greeting "$g" --greet-align center \
      --asterisks --asterisks-char '●' \
      --theme 'border=white;text=white;prompt=white;time=darkgray;action=darkgray;button=white;container=black;input=white' \
      --width 52 --cmd Hyprland
  '';
in
{
  imports = [ ./apps.nix ];

  config = lib.mkIf cfg.gui.enable {
    programs.hyprland.enable = true;

    services.greetd = {
      enable = true;
      useTextGreeter = true; # 底座设置（tuigreet 通用，非彩蛋）：避免启动日志刷进 TUI
      settings.default_session = {
        command =
          if cfg.eggs.enable then
            "${greeter}"
          else
            "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
        user = "greeter";
      };
    };

    # 音频
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # EFDS 字体体系：IBM Plex Mono 为核心等宽/展示字体
    fonts = {
      packages = with pkgs; [
        ibm-plex
        jetbrains-mono
        inter
        noto-fonts-cjk-sans
      ];
      fontconfig.defaultFonts = {
        monospace = [
          "IBM Plex Mono"
          "JetBrains Mono"
          "Noto Sans CJK SC"
        ];
        sansSerif = [
          "Inter"
          "Noto Sans CJK SC"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
      alacritty
      fuzzel
      wl-clipboard
      grim
      slurp
    ];

    # 用户态视觉层（Waybar 呼吸灯、Hyprland 单色主题、Zed EFDS 主题）
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${cfg.user.name} = import ../../home/echo.nix;
    };
  };
}
