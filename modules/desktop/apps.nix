# 必备应用集成（CLAUDE.MD §2B）：Lace、Ledger、Zed、Chrome 策略
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;

  # Lace 官方发行形态是浏览器扩展（Chrome Web Store），
  # 通过 Chrome 企业策略强制安装实现「声明式打入桌面、开箱即用」。
  laceExtensionId = "gafhhkghbfjjkeiendhlofajokpaflmk";
in
{
  config = lib.mkIf cfg.gui.enable {
    # 2. Ledger 硬件钱包：随插随用
    hardware.ledger.enable = true;
    services.udev.packages = [ pkgs.ledger-udev-rules ];

    # 3. Zed Editor（EFDS 主题与语言插件在 home/echo.nix 中声明）
    environment.systemPackages = with pkgs; [
      zed-editor
      google-chrome
    ];

    # 4. Google Chrome 策略：主页与新标签页强制锁定 + Lace 扩展强制安装
    programs.chromium = {
      enable = true;
      extraOpts = {
        HomepageLocation = "https://echoforgellc.tech";
        HomepageIsNewTabPage = false;
        NewTabPageLocation = "https://echoforgellc.tech";
        RestoreOnStartup = 4; # 4 = 打开固定网址列表
        RestoreOnStartupURLs = [
          "https://echoforgellc.tech"
          "https://stickmancharles.com"
        ];
        # 1. Lace Wallet 开箱即用
        ExtensionInstallForcelist = [
          "${laceExtensionId};https://clients2.google.com/service/update2/crx"
        ];
      };
    };
  };
}
