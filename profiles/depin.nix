# Profile 4 — echoforge-depin（DePIN 边缘节点 / 无人值守边缘设备）
# 极简无头：无 GUI、ZRAM/Swap、watchdog、断电自愈
#
# 本文件**架构无关**：x86_64 迷你主机与 aarch64 单板机共用同一套策略。
# 与具体硬件相关的东西一律拆成叠加层，不要写进这里：
#   depin-hw-rpi4.nix    — RPi4 专属（extlinux 引导、板载 ACT LED）
#   depin-layout-ssd.nix — 正式部署（tmpfs 根 + SSD 标签分区，等效只读根）
#   depin-layout-sd.nix  — 可烧录 SD 镜像（根落在 NIXOS_SD，用于首启/试用）
#
# 默认引导沿用 base.nix 的 systemd-boot/UEFI —— 对得上绝大多数 x86 迷你主机；
# 需要别的引导方式（如 RPi 的 extlinux）由硬件叠加层覆盖。
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

  # ── 内存策略：ZRAM 优先，Swap 兜底（swap 分区在 layout-ssd 中声明）──
  # 注意：Cardano 全节点在链尖实测占用约 3.1 GB、账本重放峰值 3.3 GB，
  # 且重放瓶颈是内存不是 CPU。ZRAM 只能缓解不能消除 —— 物理内存低于 8 GB
  # 的设备不要开 mithril.enable，选型见 depin-hw-rpi4.nix 顶部的提醒。
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
