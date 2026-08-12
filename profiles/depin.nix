# Profile 4 — echoforge-depin（DePIN 边缘节点 / RPi4, aarch64-linux）
# 极简无头：无 GUI、ZRAM/SSD Swap、断电自愈
# 磁盘布局按形态拆分：
#   depin-layout-ssd.nix — 正式部署（tmpfs 根 + SSD 标签分区，等效只读根）
#   depin-layout-sd.nix  — 可烧录 SD 镜像（根落在 NIXOS_SD，用于首启/试用）
{ lib, ... }:
{
  networking.hostName = "echoforge-depin";

  echoforge = {
    profile = "depin";
    gui.enable = false; # 剥离所有 GUI 组件
    node = {
      devnet.enable = false;
      # aarch64 节点二进制已就位（cardano-node 来自 Armada Alliance 静态构建，
      # mithril-client 官方 arm64）—— 单元仅由 ef-cli 拉起，绝不开机自启。
      mithril.enable = true;
      # RPi4 上索引层（Ogmios+Kupo，已有 aarch64 构建物）默认关闭以省内存；需要时置 true 重建
      indexers.enable = false;
    };
  };

  # ── 引导（RPi4：extlinux，而非 systemd-boot/EFI）──
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # ── 内存策略：ZRAM 优先，SSD Swap 兜底（swap 分区在 layout-ssd 中声明）──
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 150;
  };

  # ── 断电自愈与长效运行 ──
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "2min";
  };
  boot.kernelParams = [ "panic=10" ];
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';

  # 主机密钥固定落在持久化数据目录（tmpfs 根下 /etc/ssh 不持久），
  # 同时保证 sops-nix (age.sshKeyPaths) 跨重启可解密
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/var/lib/echoforge/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
  sops.age.sshKeyPaths = lib.mkForce [ "/var/lib/echoforge/ssh/ssh_host_ed25519_key" ];
  networking.firewall.allowedTCPPorts = [ 22 ];

  # 无头精简
  documentation.enable = false;
  environment.defaultPackages = lib.mkForce [ ];
}
