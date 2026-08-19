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
  version = "11.0.1";

  # Armada Alliance 压缩包顶层目录名（含 GHC 版本后缀）
  armadaDir = "cardano-11_0_1-aarch64-static-musl-ghc_9122";

  srcs = {
    x86_64-linux = {
      src = fetchurl {
        # 11.0.0 起上游改了资产命名：-linux.tar.gz → -linux-amd64.tar.gz
        url = "https://github.com/IntersectMBO/cardano-node/releases/download/${version}/cardano-node-${version}-linux-amd64.tar.gz";
        hash = "sha256-QOiKVDVkJRM4xIiO95/eUdIwbBi0isMIyeqzIg46E/A=";
      };
      binDir = "bin";
      shareDir = "share";
    };
    aarch64-linux = {
      src = fetchurl {
        url = "https://github.com/armada-alliance/cardano-node-binaries/raw/main/static-binaries/${armadaDir}.tar.zst";
        hash = "sha256-DWciGdCiVtNiMk0oFVQ6miauRT09zsEKzvWkYo3BTCA=";
      };
      binDir = armadaDir;
      shareDir = "${armadaDir}/share";
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

    # 上游发布件自带各网络的 config/topology/genesis。用它们而不是运行期从
    # book.world.dev.cardano.org 抓「最新」—— 网页配置永远跟着最新节点走，
    # 和被钉住的二进制迟早对不上（10.1.4 就死在解析不了新版的
    # "PrometheusSimple ..." 追踪后端上）。同包发布 = 版本天然一致，
    # 而且节点启动不再需要联网。
    mkdir -p $out/share/cardano
    cp -r ${perArch.shareDir}/* $out/share/cardano/
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
