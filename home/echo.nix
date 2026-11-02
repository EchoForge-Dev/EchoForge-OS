# 默认用户的 Home Manager 配置：EFDS 视觉层落地
# 末尾「彩蛋层」段落：Waybar 隐藏 motto / 纪念日模块、SUPER+` About This Forge、F-O-R-G-E、fuzzel 品牌化。
# 全部零闲置成本（无 exec 的静态 label、每小时一次 test、按键触发的临时终端）。
{
  pkgs,
  lib,
  osConfig,
  ...
}:
let
  eggs = osConfig.echoforge.eggs.enable;
  zh = lib.hasPrefix "zh" osConfig.i18n.defaultLocale;

  # SUPER+` —— About This Forge：球标 + 系统信息 + Stickman（复用 ef-cli，单一艺术源）
  efAbout = pkgs.writeShellApplication {
    name = "ef-about";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      gnused
    ];
    text = ''
      clear
      ef-cli version
      gen=$(readlink /nix/var/nix/profiles/system 2> /dev/null | sed -E 's/.*-([0-9]+)-link$/\1/') || gen='?'
      printf '  %-9s %s\n' KERNEL "$(uname -r)"
      printf '  %-9s %s\n' UPTIME "$(uptime -p | sed 's/^up //')"
      printf '  %-9s #%s\n' GEN "''${gen:-?}"
      echo
      ef-cli stickman
      printf '\n  [ANY KEY]\n'
      read -r -n1 -s _ || true
    '';
  };

  # 拼出 F-O-R-G-E 后的全屏横幅（静态：无揭幕动画）
  efForge = pkgs.writeShellApplication {
    name = "ef-forge";
    runtimeInputs = with pkgs; [
      ncurses
      coreutils
    ];
    text = ''
      tput civis 2> /dev/null || true
      clear
      ef-cli logo
      printf '\n  ECHOFORGE OS · FORGED 2026-04-11\n'
      read -r -n1 -s -t 3 _ || true
      tput cnorm 2> /dev/null || true
    '';
  };

  # 一年一度的 Waybar 模块（exec-if 只在 04-11 成立；tooltip 为纯 ASCII 球标，Pango 安全）
  efGenesisDay = pkgs.writeShellApplication {
    name = "ef-genesis-day";
    runtimeInputs = with pkgs; [
      jq
      coreutils
    ];
    text = ''
      t="GENESIS DAY · YEAR $(( $(date +%Y) - 2026 ))"
      # mark-small（16×7，纯 ASCII）—— 逐行 printf，避免多行字面量被格式化器改缩进
      tip=$(printf '%s\n' \
        '    _.-~~-._' \
        ' ~-.__.-~~-.__.' \
        '-~~-.__.-~~-.__.' \
        '-~~-.__.-~~-.__.' \
        '-~~-.__.-~~-.__.' \
        ' -~~-.__.-~~-._' \
        '    ~-.__.-~')
      jq -cn --arg t "$t" --arg tip "<tt>$tip</tt>"$'\n'"ECHOFORGE · est. 2026-04-11 · ALL FOR SIMPLE" \
        '{text: $t, class: "anniversary", tooltip: $tip}'
    '';
  };
in
{
  home.stateVersion = "25.05";

  # ── Waybar：状态栏 + ef-cli 节点呼吸灯绑定 ──
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      # 隐藏 motto 挂在左侧工作区之后：不影响时钟居中；透明 label，悬停显形（见 CSS）
      modules-left = [ "hyprland/workspaces" ] ++ lib.optional eggs "custom/motto";
      modules-center = [ "clock" ];
      modules-right = lib.optional eggs "custom/efday" ++ [
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
    }
    // lib.optionalAttrs eggs {
      # 工作区右侧"刻"着看不见的 motto：无 exec、无进程，只是一个透明的 label（CSS :hover 显形）
      "custom/motto" = {
        format = "ALL FOR SIMPLE";
        tooltip = false;
      };
      # 364 天不渲染：exec-if 失败时 Waybar 连占位都不画；每小时一次 test
      "custom/efday" = {
        exec-if = "test \"$(date +%m-%d)\" = 04-11";
        exec = "${efGenesisDay}/bin/ef-genesis-day";
        return-type = "json";
        interval = 3600;
        tooltip = true;
      };
    };
    style = builtins.readFile ./waybar-style.css;
  };

  # ── Hyprland：单色工程感（EFDS：白描边、深灰非活动、8px 圆角）──
  # Hyprland 0.57 删除了 hyprlang（hyprland.conf），只读 Lua（hyprland.lua）。
  # Home Manager 把 settings 的每个键渲染成一次 hl.<键>(…) 调用；dispatcher 用 mkLuaInline 原样写 Lua。
  wayland.windowManager.hyprland =
    let
      lua = lib.generators.mkLuaInline;
      str = builtins.toJSON; # Nix 字符串 → Lua 字符串字面量
      # SUPER 组合键：bind "SHIFT + M" "hl.dsp.exit()" → hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())
      bind = keys: dsp: { _args = [ (lua "mod .. ${str " + ${keys}"}") (lua dsp) ]; };
      # submap 里的单键，不带修饰键
      key = k: dsp: { _args = [ k (lua dsp) ]; };
      exec = cmd: "hl.dsp.exec_cmd(${str cmd})";
      submap = name: "hl.dsp.submap(${str name})";
      # 每一级都有 escape + catchall 双保险，任何其他键静默重置，不会锁键盘
      reset = [
        (key "escape" (submap "reset"))
        (key "catchall" (submap "reset"))
      ];
    in
    {
      enable = true;
      configType = "lua";
      settings = {
        mod._var = "SUPER";
        monitor = {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        };
        on._args = [
          "hyprland.start"
          (lua ''
            function()
              hl.exec_cmd("waybar")
            end'')
        ];

        config = {
          general = {
            gaps_in = 8;
            gaps_out = 16;
            border_size = 1;
            col = {
              active_border = "rgba(ffffffff)";
              inactive_border = "rgba(262626ff)";
            };
          };
          decoration.rounding = 8;
          misc = {
            disable_hyprland_logo = true;
            background_color = lua "0x000000";
          };
        };

        bind = [
          (bind "Return" (exec "alacritty"))
          (bind "D" (exec "fuzzel"))
          (bind "B" (exec "google-chrome-stable"))
          (bind "E" (exec "zeditor"))
          (bind "Q" "hl.dsp.window.close()")
          (bind "SHIFT + M" "hl.dsp.exit()")
          (bind "F" "hl.dsp.window.fullscreen()")
          (bind "H" ''hl.dsp.focus({ direction = "left" })'')
          (bind "L" ''hl.dsp.focus({ direction = "right" })'')
          (bind "K" ''hl.dsp.focus({ direction = "up" })'')
          (bind "J" ''hl.dsp.focus({ direction = "down" })'')
        ]
        ++ lib.concatMap (
          n:
          let
            i = toString n;
          in
          [
            (bind i "hl.dsp.focus({ workspace = ${i} })")
            (bind "SHIFT + ${i}" "hl.dsp.window.move({ workspace = ${i} })")
          ]
        ) [ 1 2 3 4 ]
        ++ lib.optionals eggs [
          # SUPER+` → About This Forge（special workspace，首次打开为空时才拉起一个临时终端）
          (bind "grave" ''hl.dsp.workspace.toggle_special("forge")'')
          # SUPER+SHIFT+F 进入静默 submap，接着拼 O-R-G-E（见 submaps）
          (bind "SHIFT + F" (submap "forge"))
        ];
      }
      // lib.optionalAttrs eggs {
        workspace_rule = {
          workspace = "special:forge";
          on_created_empty = "alacritty --class ef-about -e ef-about";
        };
        window_rule = [
          {
            match.class = "^(ef-about)$";
            float = true;
            size = "760 520";
            center = true;
          }
          {
            match.class = "^(ef-forge)$";
            fullscreen = true;
          }
        ];
      };

      # F-O-R-G-E：逐级 submap；最后一级 onDispatch = "reset"，拉起终端后立即回到默认按键
      submaps = lib.mkIf eggs {
        forge.settings.bind = [ (key "O" (submap "forge_o")) ] ++ reset;
        forge_o.settings.bind = [ (key "R" (submap "forge_r")) ] ++ reset;
        forge_r.settings.bind = [ (key "G" (submap "forge_g")) ] ++ reset;
        forge_g = {
          onDispatch = "reset";
          settings.bind = [ (key "E" (exec "alacritty --class ef-forge -e ef-forge")) ] ++ reset;
        };
      };
    };

  # Hyprland 0.57 首次启动时若没有 hyprland.lua，会自己写一份默认配置；
  # force 让 Home Manager 覆盖它，而不是因「文件已存在」中止激活。
  xdg.configFile."hypr/hyprland.lua".force = true;

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

  # ── fuzzel：黑底白边、IBM Plex Mono、占位为 motto；隐藏关键词（charles / stickman / 0411 …）──
  programs.fuzzel = lib.mkIf eggs {
    enable = true;
    settings = {
      main = {
        font = "IBM Plex Mono:size=12";
        prompt = "\"› \"";
        placeholder = if zh then "一切为简" else "ALL FOR SIMPLE";
        icons-enabled = "no";
        fields = "filename,name,generic,keywords";
        lines = 8;
        width = 40;
        horizontal-pad = 16;
        vertical-pad = 12;
      };
      colors = {
        background = "000000f2";
        text = "ffffffff";
        prompt = "808080ff";
        placeholder = "808080ff";
        input = "ffffffff";
        match = "ffffffff";
        selection = "262626ff";
        selection-text = "ffffffff";
        selection-match = "ffffffff";
        border = "ffffffff";
      };
      border = {
        width = 1;
        radius = 8;
      };
    };
  };

  # 条目名里没有这些词 —— 只有输入 charles / stickman / 0411 / echo / forge 才浮现
  xdg.desktopEntries = lib.mkIf eggs {
    ef-forge = {
      name = "FORGE";
      comment = "EchoForge · All for Simple";
      exec = "alacritty --class ef-forge -e ef-forge";
      terminal = false;
      categories = [ "Utility" ];
      settings.Keywords = "echoforge;charles;stickman;0411;forge;echo;";
    };
    ef-about = {
      name = "ABOUT THIS FORGE";
      comment = "EchoForge OS · About";
      exec = "alacritty --class ef-about -e ef-about";
      terminal = false;
      categories = [ "Utility" ];
      settings.Keywords = "about;echoforge;charles;stickman;0411;";
    };
  };

  home.packages = lib.optionals eggs [
    efAbout
    efForge
  ];

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
