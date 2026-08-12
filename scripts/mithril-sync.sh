# ef-mithril-sync <network> — Mithril 快照恢复（writeShellApplication 脚本体）
# 幂等：数据库已存在时直接跳过，重复 start 无副作用

NETWORK="${1:?usage: ef-mithril-sync <preview|preprod|mainnet>}"
STATE="${STATE_DIRECTORY:-/var/lib/echoforge/$NETWORK}"

if [ -d "$STATE/db/immutable" ]; then
  echo "==> $NETWORK database already present, skipping snapshot download"
  exit 0
fi

case "$NETWORK" in
  preview)
    AGGREGATOR_ENDPOINT="https://aggregator.pre-release-preview.api.mithril.network/aggregator"
    VKEY_DIR="pre-release-preview"
    ;;
  preprod)
    AGGREGATOR_ENDPOINT="https://aggregator.release-preprod.api.mithril.network/aggregator"
    VKEY_DIR="release-preprod"
    ;;
  mainnet)
    AGGREGATOR_ENDPOINT="https://aggregator.release-mainnet.api.mithril.network/aggregator"
    VKEY_DIR="release-mainnet"
    ;;
  *)
    echo "unknown network: $NETWORK" >&2
    exit 1
    ;;
esac

# 创世校验公钥是公开材料（非密钥），从官方仓库获取
GENESIS_VERIFICATION_KEY="$(curl -fsSL --retry 5 \
  "https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/$VKEY_DIR/genesis.vkey")"

export AGGREGATOR_ENDPOINT GENESIS_VERIFICATION_KEY

echo "==> Downloading latest certified $NETWORK snapshot via Mithril"
mithril-client cardano-db download latest --download-dir "$STATE"

echo "==> Snapshot restored to $STATE/db"
