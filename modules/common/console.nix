# Linux 虚拟控制台按 EFDS 上色：黑白灰 + 四态状态色只留给"表示状态"的地方。
#   索引 0–7：黑 / ERROR / LIVE / BETA / IN-DEV / 三档灰
#   索引 8–15：亮色 —— 8 深灰，9–12 仍是四态状态色（systemd 的粗体 [ OK ] / [FAILED] 在 VNC / RPi
#              救援控制台上必须保持绿 / 红），13–14 浅灰，15 白
# 纯内核命令行参数（vt.default_*），无守护进程、无运行时文件、零启动开销。
# GUI Profile 上换 Terminus 控制台字体（IBM437 默认字体没有 ●，tuigreet 的密码掩码需要它）。
# bash 提示符改为白 / 粗体白（NixOS 默认的亮绿在这套调色板下等于 LIVE 色 —— 状态色不该常驻提示符）。
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
  config = lib.mkIf cfg.eggs.enable {
    console.colors = [
      "000000" # 0 black
      "ef4444" # 1 red    · ERROR
      "4ade80" # 2 green  · LIVE
      "facc15" # 3 yellow · BETA
      "60a5fa" # 4 blue   · IN DEVELOPMENT
      "808080" # 5 magenta → --echo-gray
      "c0c0c0" # 6 cyan    → --echo-light-gray
      "e0e0e0" # 7 white   → --echo-light-smoke
      "404040" # 8  bright black → --smoke-dark
      "ef4444" # 9  bright red    (bold [FAILED])
      "4ade80" # 10 bright green  (bold [  OK  ])
      "facc15" # 11 bright yellow
      "60a5fa" # 12 bright blue
      "c0c0c0" # 13 bright magenta
      "e0e0e0" # 14 bright cyan
      "ffffff" # 15 bright white
    ];

    console.font = lib.mkIf cfg.gui.enable "ter-v16n";
    console.packages = lib.mkIf cfg.gui.enable [ pkgs.terminus_font ];

    programs.bash.promptInit = ''
      # EFDS 单色提示符：普通用户白色，root 粗体白（结构同 NixOS 默认，只换颜色）
      if [ "$TERM" != "dumb" ] || [ -n "$INSIDE_EMACS" ]; then
        PROMPT_COLOR="1;37m"
        ((UID)) && PROMPT_COLOR="0;37m"
        if [ -n "$INSIDE_EMACS" ]; then
          PS1="\n\[\033[$PROMPT_COLOR\][\u@\h:\w]\\$\[\033[0m\] "
        else
          PS1="\n\[\033[$PROMPT_COLOR\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\\$\[\033[0m\] "
        fi
        if test "$TERM" = "xterm"; then
          PS1="\[\033]2;\h:\u:\w\007\]$PS1"
        fi
      fi
    '';
  };
}
