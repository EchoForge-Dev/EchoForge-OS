#!/usr/bin/env bash
# 打印各上游静态发布件的 SRI 哈希，替换/核对 pkgs/cardano/*.nix 中的哈希
# 用法: ./scripts/prefetch-hashes.sh   (需要 nix ≥ 2.4)
set -euo pipefail

urls=(
  # cardano-node（x86_64 官方 / aarch64 Armada Alliance）
  "https://github.com/IntersectMBO/cardano-node/releases/download/10.1.4/cardano-node-10.1.4-linux.tar.gz"
  "https://github.com/armada-alliance/cardano-node-binaries/raw/main/static-binaries/cardano-10_1_4-aarch64-static-musl-ghc_966.tar.zst"
  # ogmios
  "https://github.com/CardanoSolutions/ogmios/releases/download/v6.14.0/ogmios-v6.14.0-x86_64-linux.zip"
  "https://github.com/CardanoSolutions/ogmios/releases/download/v6.14.0/ogmios-v6.14.0-aarch64-linux.zip"
  # kupo（注意：tag 只有主次位 v2.12，文件名带补丁位 v2.12.0）
  "https://github.com/CardanoSolutions/kupo/releases/download/v2.12/kupo-v2.12.0-x86_64-linux.zip"
  "https://github.com/CardanoSolutions/kupo/releases/download/v2.12/kupo-v2.12.0-aarch64-linux.zip"
  # mithril
  "https://github.com/input-output-hk/mithril/releases/download/2630.0/mithril-2630.0-linux-x64.tar.gz"
  "https://github.com/input-output-hk/mithril/releases/download/2630.0/mithril-2630.0-linux-arm64.tar.gz"
)

for url in "${urls[@]}"; do
  echo "== $url"
  nix store prefetch-file --json "$url" | jq -r '.hash'
  echo
done

echo "把上面的 sha256-... 依次填入 pkgs/cardano/{node-bin,ogmios,kupo,mithril-client}.nix"
echo "若某个 URL 404，说明上游改了版本号或文件名 —— 打开对应 GitHub Releases 页核对后同步更新 version/url。"
