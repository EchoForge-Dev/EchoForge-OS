# ef-node-run <network> — 运行 mithril 引导的全节点（writeShellApplication 脚本体）
# 首次启动自动从官方环境端点获取网络配置（config/topology/genesis）

NETWORK="${1:?usage: ef-node-run <preview|preprod|mainnet>}"
STATE="${STATE_DIRECTORY:-/var/lib/echoforge/$NETWORK}"
RUN_DIR="${RUNTIME_DIRECTORY:-/run/echoforge}"
HOST="${EF_HOST:-127.0.0.1}"
PORT="${EF_PORT:-3001}"

CFG_DIR="$STATE/config"
BASE_URL="https://book.world.dev.cardano.org/environments/$NETWORK"

FETCH_FILES=(config.json byron-genesis.json shelley-genesis.json alonzo-genesis.json conway-genesis.json)

# 自有拓扑（Nix 生成，出块节点/中继必备）时不拉官方公共 topology.json
TOPOLOGY="${EF_TOPOLOGY:-}"
if [ -z "$TOPOLOGY" ]; then
  FETCH_FILES+=(topology.json)
  TOPOLOGY="$CFG_DIR/topology.json"
fi

mkdir -p "$CFG_DIR"
for f in "${FETCH_FILES[@]}"; do
  if [ ! -s "$CFG_DIR/$f" ]; then
    echo "==> Fetching $NETWORK/$f"
    curl -fsSL --retry 5 -o "$CFG_DIR/$f.tmp" "$BASE_URL/$f"
    mv "$CFG_DIR/$f.tmp" "$CFG_DIR/$f"
  fi
done

[ -r "$TOPOLOGY" ] || {
  echo "==> topology not readable: $TOPOLOGY" >&2
  exit 1
}

ln -sf "$CFG_DIR/config.json" "$RUN_DIR/node-config.json"
# ef-cli pool 子命令要按网络算 KES period，需要 shelley 创世
ln -sf "$CFG_DIR/shelley-genesis.json" "$RUN_DIR/shelley-genesis.json"

# SPO 出块模式：三个环境变量（由 mithril.nix 在 blockProducer.enable 时注入）
# 齐备且可读时，追加 KES/VRF/OpCert 出块参数；密钥路径指向 /run/secrets，绝不落盘
EXTRA_ARGS=()
if [ -n "${EF_KES_KEY:-}" ] && [ -n "${EF_VRF_KEY:-}" ] && [ -n "${EF_OP_CERT:-}" ]; then
  for f in "$EF_KES_KEY" "$EF_VRF_KEY" "$EF_OP_CERT"; do
    if [ ! -r "$f" ]; then
      echo "==> block producer key not readable: $f (check sops-nix pool/* secrets)" >&2
      exit 1
    fi
  done
  echo "==> Block producer mode enabled (KES/VRF/OpCert via sops-nix)"
  EXTRA_ARGS+=(
    --shelley-kes-key "$EF_KES_KEY"
    --shelley-vrf-key "$EF_VRF_KEY"
    --shelley-operational-certificate "$EF_OP_CERT"
  )
fi

echo "==> Starting $NETWORK node on $HOST:$PORT (socket: $RUN_DIR/node.socket)"
echo "==> Topology: $TOPOLOGY"
exec cardano-node run \
  --config "$CFG_DIR/config.json" \
  --topology "$TOPOLOGY" \
  --database-path "$STATE/db" \
  --socket-path "$RUN_DIR/node.socket" \
  --host-addr "$HOST" \
  --port "$PORT" \
  "${EXTRA_ARGS[@]}"
