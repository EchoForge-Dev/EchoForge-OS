# Kupo：轻量 Cardano UTxO 索引器（官方静态发布件，x86_64 + aarch64）
# 注意：上游 Release tag 只有主次位（v2.12），资产文件名才带补丁位（v2.12.0）
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
let
  hashes = {
    x86_64-linux = "sha256-iItcJsD7raevdbplQoILdiSdeeBqxvr2SXra1QI8ajs=";
    aarch64-linux = "sha256-8nKJzlRwO/978o5sLtrKLT77+KUGBb+YrSD+5Z3piK4=";
  };
  arch = stdenvNoCC.hostPlatform.parsed.cpu.name; # x86_64 | aarch64
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kupo";
  version = "2.12.0";

  src = fetchurl {
    url = "https://github.com/CardanoSolutions/kupo/releases/download/v${lib.versions.majorMinor finalAttrs.version}/kupo-v${finalAttrs.version}-${arch}-linux.zip";
    hash =
      hashes.${stdenvNoCC.hostPlatform.system}
        or (throw "kupo: unsupported system ${stdenvNoCC.hostPlatform.system}");
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 bin/kupo $out/bin/kupo
    runHook postInstall
  '';

  meta = {
    description = "Fast, lightweight & configurable chain-index for Cardano";
    homepage = "https://github.com/CardanoSolutions/kupo";
    license = lib.licenses.mpl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "kupo";
  };
})
