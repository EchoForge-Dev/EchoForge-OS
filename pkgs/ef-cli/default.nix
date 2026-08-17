{ lib, writeShellApplication }:

writeShellApplication {
  name = "ef-cli";
  # systemctl / sudo / nixos-rebuild 使用宿主系统的实现，不打入闭包。
  # pool 子命令另需 cardano-cli 与 jq —— 由 modules/cardano 与 common/base
  # 装进 systemPackages，同样走宿主 PATH，避免 CLI 闭包里塞一份节点二进制。
  runtimeInputs = [ ];
  text = builtins.readFile ./ef-cli.sh;

  meta = {
    description = "EchoForge OS dynamic node engine & profile manager";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ef-cli";
  };
}
