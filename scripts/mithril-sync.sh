# ef-mithril-sync <network> — Mithril 快照恢复（writeShellApplication 脚本体）
# 幂等：数据库已存在时直接跳过，重复 start 无副作用

NETWORK="${1:?usage: ef-mithril-sync <preview|preprod|mainnet>}"
STATE="${STATE_DIRECTORY:-/var/lib/echoforge/$NETWORK}"

# 幂等哨兵盯的是「下载成功」这一事实，而不是「目录存在」。
# 差别很实在：快照恢复中途断电 / 重启 / OOM 时，db/immutable 已经建好并塞了
# 几万个文件，只是不完整；用目录做哨兵会让下一次同步直接跳过，
# 然后节点在一条截断的链上启动 —— 对 depin 的「断电自愈」是致命的。
COMPLETE_MARKER="$STATE/db/.ef-mithril-complete"

if [ -f "$COMPLETE_MARKER" ]; then
  echo "==> $NETWORK database already present, skipping snapshot download"
  exit 0
fi

if [ -d "$STATE/db" ]; then
  echo "==> found an incomplete $NETWORK database (no completion marker) — discarding and re-downloading" >&2
  rm -rf "$STATE/db"
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

# 只有走到这一步（download 返回 0）才落标记 —— 中途死掉不会留下假的「已完成」
touch "$COMPLETE_MARKER"

echo "==> Snapshot restored to $STATE/db"
echo "    ✓ certified by many, verified by you"
