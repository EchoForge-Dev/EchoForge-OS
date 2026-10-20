# mithril-client：Mithril 认证快照客户端（官方静态发布件，x86_64 + aarch64）
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  perArch = {
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-q6TWdcLBz2K/FnSKnUSOGhW/QQoUIwbmVI38w47olQA=";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha256-Ihb0Dh1uRuBIZt9rLnyhvl33veMstPQwXve3Tv1DtF8=";
    };
  };
  asset =
    perArch.${stdenvNoCC.hostPlatform.system}
      or (throw "mithril-client-bin: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mithril-client-bin";
  version = "2642.0";

  src = fetchurl {
    url = "https://github.com/input-output-hk/mithril/releases/download/${finalAttrs.version}/mithril-${finalAttrs.version}-${asset.suffix}.tar.gz";
    inherit (asset) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 mithril-client $out/bin/mithril-client
    runHook postInstall
  '';

  meta = {
    description = "Mithril client — certified Cardano snapshot bootstrap";
    homepage = "https://github.com/input-output-hk/mithril";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "mithril-client";
  };
})
