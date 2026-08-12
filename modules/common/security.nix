# 安全禁令（CLAUDE.MD §4）：严格网络隔离 + 本地端口不出网
{ config, lib, ... }:
let
  cfg = config.echoforge;
in
{
  # 默认拒绝一切入站；节点/Ogmios/Kupo 端口永不加入 allowedTCPPorts
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # SSH 由 spo/depin Profile 显式开启；一旦开启即强制密钥登录
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  # 基础内核加固
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
  };

  # 无头机器防锁死：SSH 已强制密钥登录且用户不可变，
  # 开了 sshd 却没有声明任何公钥时在构建期给出显式警告
  warnings = lib.optional (config.services.openssh.enable && cfg.user.sshKeys == [ ]) ''
    services.openssh 已启用但 echoforge.user.sshKeys 为空。
    密钥登录被强制（PasswordAuthentication=false）且 users.mutableUsers=false，
    部署后将无法 SSH 进入，只能靠 VNC/串口控制台救援 —— 请在 Profile 中声明公钥。
  '';

  # 把「RPC 只绑 127.0.0.1」升格为构建期硬约束：
  # 想改成对外地址必须显式改 Nix 配置并重新构建，运行期无法绕过
  assertions = [
    {
      assertion = cfg.profile == "spo" || cfg.node.hostAddr == "127.0.0.1";
      message = ''
        echoforge.node.hostAddr 必须为 127.0.0.1（仅 spo Profile 允许显式放开）。
        本地节点 RPC/WebSocket 端口默认禁止对外暴露 —— CLAUDE.MD §4.3。
      '';
    }
  ];
}
