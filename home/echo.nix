# 默认用户的 Home Manager 配置：EFDS 视觉层落地
{ pkgs, ... }:
{
  home.stateVersion = "25.05";

  # ── Waybar：状态栏 + ef-cli 节点呼吸灯绑定 ──
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [
        "custom/efnode"
        "cpu"
        "memory"
        "network"
        "battery"
      ];

      "custom/efnode" = {
        exec = "ef-cli node status --waybar";
        return-type = "json";
        interval = 3;
        tooltip = true;
      };

      clock.format = "{:%Y-%m-%d %H:%M}";
      cpu.format = "CPU {usage}%";
      memory.format = "MEM {percentage}%";
      network = {
        format-wifi = "NET {essid}";
        format-ethernet = "NET eth";
        format-disconnected = "NET --";
      };
      battery.format = "BAT {capacity}%";
    };
    style = builtins.readFile ./waybar-style.css;
  };

  # ── Hyprland：单色工程感（EFDS：白描边、深灰非活动、8px 圆角）──
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = [ ",preferred,auto,1" ];
      exec-once = [ "waybar" ];

      general = {
        gaps_in = 8;
        gaps_out = 16;
        border_size = 1;
        "col.active_border" = "rgba(ffffffff)";
        "col.inactive_border" = "rgba(262626ff)";
      };

      decoration = {
        rounding = 8;
      };

      misc = {
        disable_hyprland_logo = true;
        background_color = "0x000000";
      };

      "$mod" = "SUPER";
      bind = [
        "$mod, Return, exec, alacritty"
        "$mod, D, exec, fuzzel"
        "$mod, B, exec, google-chrome-stable"
        "$mod, E, exec, zeditor"
        "$mod, Q, killactive"
        "$mod SHIFT, M, exit"
        "$mod, F, fullscreen"
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
      ];
    };
  };

  # ── Alacritty：纯黑白灰终端 ──
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal.family = "IBM Plex Mono";
        size = 13;
      };
      window.padding = {
        x = 16;
        y = 16;
      };
      colors = {
        primary = {
          background = "#000000";
          foreground = "#ffffff";
        };
        cursor = {
          text = "#000000";
          cursor = "#ffffff";
        };
        normal = {
          black = "#000000";
          red = "#ef4444";
          green = "#4ade80";
          yellow = "#facc15";
          blue = "#60a5fa";
          magenta = "#c0c0c0";
          cyan = "#e0e0e0";
          white = "#ffffff";
        };
      };
    };
  };

  # ── Zed：EFDS 暗黑高对比主题 + Aiken/Haskell/Nix 插件 ──
  xdg.configFile."zed/themes/echoforge.json".source = ./zed-theme.json;
  xdg.configFile."zed/settings.json".text = builtins.toJSON {
    theme = "EchoForge Dark";
    buffer_font_family = "IBM Plex Mono";
    ui_font_family = "IBM Plex Mono";
    buffer_font_size = 14;
    auto_install_extensions = {
      nix = true;
      haskell = true;
      aiken = true;
      toml = true;
    };
    telemetry = {
      diagnostics = false;
      metrics = false;
    };
  };

  # GTK 应用统一深色
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
