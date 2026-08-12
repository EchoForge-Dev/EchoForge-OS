{ lib, writeShellApplication }:

writeShellApplication {
  name = "ef-cli";
  # systemctl / sudo / nixos-rebuild 使用宿主系统的实现，不打入闭包
  runtimeInputs = [ ];
  text = builtins.readFile ./ef-cli.sh;

  meta = {
    description = "EchoForge OS dynamic node engine & profile manager";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ef-cli";
  };
}
