# 系统底座：不可变原则、Nix 设置、默认用户与基础工具
# 一切系统变更只能修改本仓库的 Nix 表达式并 nixos-rebuild —— 严禁运行期 apt/pacman/改 /etc
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
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  # 不可变系统原则：用户与密码全部声明式管理
  users.mutableUsers = false;

  users.users.${cfg.user.name} = {
    isNormalUser = true;
    description = "EchoForge default user";
    extraGroups = [
      "wheel"
      "video"
      "audio"
      "plugdev"
      "dialout"
    ];
    # 首次登录后请立即修改；生产镜像应改为 sops-nix 管理的 hashedPasswordFile
    initialPassword = "echoforge";
    # SSH 仅密钥登录（见 common/security.nix）—— 公钥在此声明式下发
    openssh.authorizedKeys.keys = cfg.user.sshKeys;
  };
  users.groups.plugdev = { };

  # ef-cli 需要免密操作自身的 systemd 单元（范围严格限定在 ef-* 前缀）
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands =
        map
          (command: {
            inherit command;
            options = [ "NOPASSWD" ];
          })
          [
            "/run/current-system/sw/bin/systemctl start ef-*"
            "/run/current-system/sw/bin/systemctl stop ef-*"
            "/run/current-system/sw/bin/systemctl restart ef-*"
          ];
    }
  ];

  environment.systemPackages = with pkgs; [
    ef-cli
    git
    vim
    htop
    jq
    curl
  ];

  # ef-cli profile switch 读取此处的 Flake 引用
  environment.etc."echoforge/flake.ref".text = cfg.flakeRef;
  environment.etc."echoforge/profile".text = cfg.profile;

  # 占位磁盘布局（安装时按标签分区即可，无需改代码）；depin 会整体覆盖
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/echoforge-root";
    fsType = lib.mkDefault "ext4";
  };
  fileSystems."/boot" = {
    device = lib.mkDefault "/dev/disk/by-label/EFOS-BOOT";
    fsType = lib.mkDefault "vfat";
  };

  boot.loader = {
    systemd-boot.enable = lib.mkDefault true;
    efi.canTouchEfiVariables = lib.mkDefault true;
  };

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "zh_CN.UTF-8/UTF-8"
  ];

  system.stateVersion = "25.05";
}
