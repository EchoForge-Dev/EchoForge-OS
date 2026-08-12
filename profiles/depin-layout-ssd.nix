# depin 正式部署磁盘布局：Read-Only 根策略
# 根为 tmpfs（每次断电重启回到干净状态 = 自愈），
# 只有 /nix（只读闭包）与 /var/lib/echoforge（节点数据）落在 SSD 上
{ lib, ... }:
{
  fileSystems."/" = lib.mkForce {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=512M"
      "mode=755"
    ];
  };
  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/echoforge-nix";
    fsType = "ext4";
    neededForBoot = true;
    options = [ "noatime" ];
  };
  fileSystems."/var/lib/echoforge" = {
    device = "/dev/disk/by-label/echoforge-data";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # 按需在 SSD 上追加 swap 分区（标签 echoforge-swap），没有该分区时注释掉本行
  swapDevices = [ { device = "/dev/disk/by-label/echoforge-swap"; } ];
}
