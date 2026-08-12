# ef-devnet-run — Local Devnet 引导脚本（writeShellApplication 脚本体）
# 首次启动生成私有链创世，此后直接复用；socket 统一暴露在 /run/echoforge/node.socket

STATE="${STATE_DIRECTORY:-/var/lib/echoforge/devnet}"
RUN_DIR="${RUNTIME_DIRECTORY:-/run/echoforge}"
MAGIC="${EF_DEVNET_MAGIC:-42}"
PORT="${EF_DEVNET_PORT:-6000}"
HOST="${EF_HOST:-127.0.0.1}"

GENESIS_DIR="$STATE/genesis"

if [ ! -f "$GENESIS_DIR/configuration.yaml" ]; then
  echo "==> First start: generating devnet genesis (magic=$MAGIC)"
  rm -rf "$GENESIS_DIR"
  cardano-cli conway genesis create-testnet-data \
    --testnet-magic "$MAGIC" \
    --genesis-keys 1 \
    --pools 1 \
    --stake-delegators 1 \
    --utxo-keys 2 \
    --total-supply 45000000000000000 \
    --out-dir "$GENESIS_DIR"
fi

# 单节点私有链：空的 P2P 拓扑
cat > "$STATE/topology.json" <<'EOF'
{
  "localRoots": [
    { "accessPoints": [], "advertise": false, "valency": 1 }
  ],
  "publicRoots": [],
  "useLedgerAfterSlot": -1
}
EOF

# 供 Ogmios / Kupo 读取的统一节点配置入口
ln -sf "$GENESIS_DIR/configuration.yaml" "$RUN_DIR/node-config.json"

echo "==> Starting devnet node on $HOST:$PORT (socket: $RUN_DIR/node.socket)"
exec cardano-node run \
  --config "$GENESIS_DIR/configuration.yaml" \
  --topology "$STATE/topology.json" \
  --database-path "$STATE/db" \
  --socket-path "$RUN_DIR/node.socket" \
  --shelley-kes-key "$GENESIS_DIR/pools-keys/pool1/kes.skey" \
  --shelley-vrf-key "$GENESIS_DIR/pools-keys/pool1/vrf.skey" \
  --shelley-operational-certificate "$GENESIS_DIR/pools-keys/pool1/opcert.cert" \
  --host-addr "$HOST" \
  --port "$PORT"
