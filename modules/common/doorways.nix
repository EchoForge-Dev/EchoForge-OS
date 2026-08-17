# 两扇通往 root 的门，用"一切为简"回答：
#   1. sudo lecture（每用户一次，仅在 sudo 真的要密码时；ef-cli 的 systemctl start/stop ef-* 免密调用不出现）
#   2. 交互式 bash 里敲 apt / pacman / brew … 时的不可变性提示（CLAUDE.MD §4）
# 两者只是文本：sudoers 只多几行 Defaults（构建期 visudo -c 校验；谁能 sudo、NOPASSWD 范围一概不变），
# shell 函数仅在交互式 shell、且命令确实不存在时触发，退出码保持 127，`command -v apt` 照样失败。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  lecture = pkgs.writeText "efos-sudo-lecture" ''
    ECHOFORGE OS . PRIVILEGED SHELL
      This machine is declarative and immutable. Hand-edits under sudo are not part of
      the configuration and will not survive the next rebuild -- change flake.nix, then
      ef-cli profile switch ${cfg.profile}
      ALL FOR SIMPLE

  '';
in
{
  config = lib.mkIf cfg.eggs.enable {
    security.sudo.extraConfig = ''
      Defaults lecture=once
      Defaults lecture_file="${lecture}"
      Defaults passprompt="[sudo] EFOS %h / password for %p: "
    '';

    programs.bash.interactiveShellInit = lib.mkAfter ''
      command_not_found_handle() {
        case "$1" in
          apt | apt-get | aptitude | dpkg | pacman | yay | paru | yum | dnf | zypper | apk | emerge | brew | snap | rpm)
            cat >&2 <<EOF
      $1: not on this machine.
      EchoForge OS is immutable — nothing installs at runtime.
        change   = rebuild : edit flake.nix, then  ef-cli profile switch ${cfg.profile}
        one tool = nix shell nixpkgs#<pkg>   (ephemeral, leaves no trace)
        ALL FOR SIMPLE
      EOF
            return 127
            ;;
          *)
            if command -v command-not-found > /dev/null 2>&1; then
              command-not-found "$@"
              return $?
            fi
            printf 'bash: %s: command not found\n' "$1" >&2
            return 127
            ;;
        esac
      }
    '';
  };
}
