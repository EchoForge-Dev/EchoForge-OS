# Ogmios：cardano-node 的 WebSocket/JSON-RPC 桥（官方静态发布件，x86_64 + aarch64）
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
let
  hashes = {
    x86_64-linux = "sha256-Y2M6xEouKEiF4I5s4NgBJpZzngV9Ch/XOD09dQxdICc=";
    aarch64-linux = "sha256-3V5v+OotWzPhtOtP4v1JQzsHCMr3O4XUOrFz2rbBpsI=";
  };
  arch = stdenvNoCC.hostPlatform.parsed.cpu.name; # x86_64 | aarch64
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ogmios";
  version = "6.14.0";

  src = fetchurl {
    url = "https://github.com/CardanoSolutions/ogmios/releases/download/v${finalAttrs.version}/ogmios-v${finalAttrs.version}-${arch}-linux.zip";
    hash =
      hashes.${stdenvNoCC.hostPlatform.system}
        or (throw "ogmios: unsupported system ${stdenvNoCC.hostPlatform.system}");
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 bin/ogmios $out/bin/ogmios
    runHook postInstall
  '';

  meta = {
    description = "WebSocket bridge for cardano-node";
    homepage = "https://github.com/CardanoSolutions/ogmios";
    license = lib.licenses.mpl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "ogmios";
  };
})
