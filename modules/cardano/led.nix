# depin（RPi4）：板载 ACT LED 变成实体呼吸灯 —— CLAUDE.MD §3 呼吸灯契约在无 Waybar 的无头机上的物理映射。
#   节点运行   → 内核 timer 触发器 1000 ms 亮 / 1000 ms 灭（EFDS 2 s 呼吸节奏）
#   快照恢复中 → 250 ms 快闪（"工作中"）
#   节点停止   → 交还内核默认 mmc0（SD 活动闪烁）—— 刻意不熄灭，无头机"还活着"的信号保留
# 闪烁由内核 LED 定时器完成：无用户态进程、无轮询、无常驻内存；开机时什么都不做，节点依旧只由 ef-cli 拉起。
# 唯一的特权点：ExecStartPost/ExecStopPost 以 `-+` 前缀运行一个不可变的 store 脚本 ——
#   `+` 仅这一行以 root 运行（sysfs 只有 root 可写；cardano-node 本体仍 User=cardano / ProtectSystem=strict /
#   NoNewPrivileges），`-` 失败被忽略：装饰永远不能让节点或 6 小时的快照恢复失败。
#   脚本只写固定常量、不接收 %i、末尾 exit 0。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.echoforge;
  ledCtl = pkgs.writeShellScript "ef-act-led" ''
    # usage: ef-act-led run|sync|off —— 装饰性助手：永不失败，永不影响节点
    for l in ACT led0; do # 主线 bcm2711 设备树叫 ACT；旧内核叫 led0
      t=/sys/class/leds/$l
      [ -w "$t/trigger" ] || continue
      case "$1" in
        run) echo timer > "$t/trigger" && echo 1000 > "$t/delay_on" && echo 1000 > "$t/delay_off" ;;
        sync) echo timer > "$t/trigger" && echo 250 > "$t/delay_on" && echo 250 > "$t/delay_off" ;;
        *) echo mmc0 > "$t/trigger" || echo none > "$t/trigger" ;; # 没有 mmc0 触发器的板子退而熄灭
      esac 2> /dev/null
      break
    done
    exit 0
  '';
in
{
  config = lib.mkIf (cfg.node.mithril.enable && cfg.node.led.enable && cfg.profile == "depin") {
    boot.kernelModules = [ "ledtrig_timer" ]; # 内建时为 no-op

    systemd.services."ef-node@".serviceConfig = {
      ExecStartPost = [ "-+${ledCtl} run" ];
      ExecStopPost = [ "-+${ledCtl} off" ];
    };
    systemd.services."ef-mithril-sync@".serviceConfig = {
      ExecStartPre = [ "-+${ledCtl} sync" ];
      ExecStopPost = [ "-+${ledCtl} off" ]; # oneshot 结束 → off；随后 ef-cli 拉起 ef-node@ → run
    };
  };
}
