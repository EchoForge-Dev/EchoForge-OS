# EchoForge GUI 底座：Hyprland + Waybar + greetd，EFDS 字体体系
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
in
{
  imports = [ ./apps.nix ];

  config = lib.mkIf cfg.gui.enable {
    programs.hyprland.enable = true;

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
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
