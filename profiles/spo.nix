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

      # 默认形态：只监听回环的观察节点，官方公共拓扑，不对外开一个端口。
      # 下面两段按角色二选一取消注释 —— 中继与出块绝不能同机同配置。

      # ── 角色 A：中继节点（Relay）────────────────────────────────
      # 对外可达 + 放行 P2P 端口，localRoots 指向自家出块节点与兄弟中继
      # hostAddr = "0.0.0.0";
      # mithril.openFirewall = true;
      # mithril.topology.localRoots = [
      #   { address = "10.0.0.10"; port = 3001; }   # 自家出块节点（内网地址）
      #   { address = "relay-2.example.com"; port = 3001; }
      # ];
      # mithril.topology.bootstrapPeers = [
      #   { address = "backbone.cardano.iog.io"; port = 3001; }
      # ];

      # ── 角色 B：出块节点（Block Producer）──────────────────────
      # 先按 secrets/README.md 把 KES/VRF/OpCert 放进 sops-nix 再启用。
      # 保持 hostAddr 内网地址、openFirewall = false：出块节点只主动外连
      # 自有中继，入站由下面的 extraInputRules 按中继 IP 精确放行。
      # mithril.blockProducer.enable = true;
      # mithril.topology.localRoots = [
      #   { address = "relay-1.example.com"; port = 3001; }
      #   { address = "relay-2.example.com"; port = 3001; }
      # ];
    };
  };

  # 出块节点入站白名单示例（配合角色 B；地址换成自家中继）。
  # extraInputRules 只在 nftables 后端可用，两行必须一起取消注释。
  # networking.nftables.enable = true;
  # networking.firewall.extraInputRules = ''
  #   ip saddr { 10.0.0.11, 10.0.0.12 } tcp dport 3001 accept
  # '';

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
