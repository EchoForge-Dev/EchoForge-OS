# Profile 3 — echoforge-spo（极客 / Protocol & Full Node）
# 高性能图形/TUI 混合监测；Mithril 快照秒级同步 Preview/Preprod/Mainnet
{ pkgs, ... }:
{
  networking.hostName = "echoforge-spo";

  echoforge = {
    profile = "spo";
    gui.enable = true;
    node = {
      devnet.enable = false;
      mithril.enable = true;
      indexers.enable = false; # SPO 默认纯节点；需要索引层时置 true 重建

      # 出块节点：先按 secrets/README.md 把 KES/VRF/OpCert 放进 sops-nix，
      # 再取消注释重建（中继节点保持注释即可）
      # mithril.blockProducer.enable = true;
    };
  };

  # TUI 监控与调优面板
  environment.systemPackages = with pkgs; [
    bottom # btm：进程/资源 TUI
    bandwhich # 每连接带宽 TUI
    iotop
    smartmontools
    lsof
  ];

  # 节点指标仅本机可见（Prometheus node exporter 绑定 127.0.0.1）
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
  };

  # 全节点网络吞吐调优
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
  };

  # 远程运维入口（仅密钥登录，见 common/security.nix）
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # 时间同步对出块节点至关重要
  services.chrony.enable = true;
}
