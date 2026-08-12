# Profile 1 — echoforge-desktop（爱好者 / Staking & Browsing）
# GUI 轻量桌面；节点模块完全不启用 → 0% CPU / 0MB RAM 节点开销
{ ... }:
{
  networking.hostName = "echoforge-desktop";

  echoforge = {
    profile = "desktop";
    gui.enable = true;
    # 节点默认完全关闭：连 systemd 单元都不安装
    node = {
      devnet.enable = false;
      mithril.enable = false;
      indexers.enable = false;
    };
  };

  # 极致安全的只读桌面：无 SSH 入口、日志限量
  services.openssh.enable = false;
  services.journald.extraConfig = ''
    SystemMaxUse=200M
  '';
}
