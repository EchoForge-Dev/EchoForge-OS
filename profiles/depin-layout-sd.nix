# depin 可烧录 SD 镜像布局（nix build .#packages.aarch64-linux.depin-sd-image）
# 根/固件挂载点由 sd-image 模块给出：/ = NIXOS_SD (ext4)、/boot/firmware = FIRMWARE (vfat)；
# 首次启动 sdImage.expandOnBoot（默认开启）自动扩容根分区。
# 数据目录 /var/lib/echoforge 直接落在 SD 根分区上 —— 与 SSH 主机密钥、
# sops-nix Age 身份的持久化路径天然对齐，无需额外分区。
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  # sd-image 默认打开 enableAllHardware，会向 linux_rpi4 内核索取其不存在的模块
  # 导致镜像构建失败；depin 是固定硬件（RPi4），按需精简
  hardware.enableAllHardware = lib.mkForce false;

  # base.nix 的占位 /boot（EFOS-BOOT 标签）在 SD 卡上不存在；条目无法删除，
  # 改为 noauto+nofail 使其既不挂载也不阻塞启动（extlinux 直接写根分区的 /boot 目录）
  fileSystems."/boot".options = [
    "noauto"
    "nofail"
  ];

  sdImage.compressImage = true; # 产出 .img.zst
}
