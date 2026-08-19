# depin 硬件叠加层 —— Raspberry Pi 4
#
# depin.nix 本身是架构无关的「无人值守边缘设备」策略（无 GUI、tmpfs 根、
# ZRAM、watchdog、断电自愈）。真正长在树莓派上的只有这几样，全部收在这里：
# 引导方式、板载 LED。磁盘布局另见 depin-layout-{ssd,sd}.nix。
#
# 换别的板子（或 x86 迷你主机）时不要改 depin.nix，写一份平行的硬件叠加层即可。
#
# ⚠ 选型提醒（2026-08-19 实机实测，见 docs 内的验收记录）：
#   Cardano 全节点在链尖占用约 3.1 GB、账本重放峰值 3.3 GB，且重放的瓶颈
#   是内存而非 CPU（账本状态随重放累积增长，逼近物理内存后开始换页，
#   速度断崖下跌）。因此：
#     · RPi4 4GB  —— 连 preview 都跑不稳，断电重放极可能 OOM 并陷入循环
#     · RPi4 8GB  —— preview 可用，mainnet 不现实
#   要跑 mainnet 请用 16GB 以上的 x86 迷你主机（走 depin 的默认 x86_64 出口）。
{ lib, ... }:
{
  # ── 引导：RPi4 走 extlinux，不是 systemd-boot/EFI ──
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # ── 板载 ACT LED 映射节点状态 ──
  # 无头机没有 Waybar，这块 LED 就是 CLAUDE.MD §3 呼吸灯契约的物理落点。
  # 实现见 modules/cardano/led.nix；没有该 LED 的硬件上不启用。
  echoforge.node.led.enable = true;
}
