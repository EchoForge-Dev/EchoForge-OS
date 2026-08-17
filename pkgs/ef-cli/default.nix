{ lib, writeShellApplication }:

writeShellApplication {
  name = "ef-cli";
  # systemctl / sudo / nixos-rebuild 使用宿主系统的实现，不打入闭包。
  # pool 子命令另需 cardano-cli 与 jq —— 由 modules/cardano 与 common/base
  # 装进 systemPackages，同样走宿主 PATH，避免 CLI 闭包里塞一份节点二进制。
  runtimeInputs = [ ];
  # 彩蛋层（eggs.sh）前置拼接：只定义函数，main "$@" 仍是 ef-cli.sh 的最后一行，
  # 定义顺序无关；两段合并后一起过 shellcheck
  text = builtins.readFile ./eggs.sh + builtins.readFile ./ef-cli.sh;

  meta = {
    description = "EchoForge OS dynamic node engine & profile manager";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ef-cli";
  };
}
