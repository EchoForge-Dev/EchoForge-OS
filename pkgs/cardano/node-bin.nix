# cardano-node + cardano-cli 静态二进制：
#   x86_64-linux  → IntersectMBO 官方静态发布件
#   aarch64-linux → Armada Alliance 社区静态构建物（musl，服务 RPi4/DePIN）
# 版本升级时运行 scripts/prefetch-hashes.sh 重新填充哈希
{
  lib,
  stdenvNoCC,
  fetchurl,
  zstd,
}:
let
  version = "10.1.4";

  # Armada Alliance 压缩包顶层目录名（含 GHC 版本后缀）
  armadaDir = "cardano-10_1_4-aarch64-static-musl-ghc_966";

  srcs = {
    x86_64-linux = {
      src = fetchurl {
        url = "https://github.com/IntersectMBO/cardano-node/releases/download/${version}/cardano-node-${version}-linux.tar.gz";
        hash = "sha256-r7gvMCWkwbhFzgjC64nI3IaS6DJvR45Oo3zh4gY/4/Y=";
      };
      binDir = "bin";
    };
    aarch64-linux = {
      src = fetchurl {
        url = "https://github.com/armada-alliance/cardano-node-binaries/raw/main/static-binaries/${armadaDir}.tar.zst";
        hash = "sha256-g2gAaD7FV8Olkk6awZ3mdG30U5+c2olLOhkADnQ377E=";
      };
      binDir = armadaDir;
    };
  };

  perArch =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "cardano-node-bin: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "cardano-node-bin";
  inherit version;
  inherit (perArch) src;

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isAarch64 [ zstd ];

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 ${perArch.binDir}/cardano-node ${perArch.binDir}/cardano-cli $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Cardano node & CLI (static release binaries; aarch64 via Armada Alliance)";
    homepage = "https://github.com/IntersectMBO/cardano-node";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
