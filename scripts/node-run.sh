# ef-node-run <network> — 运行 mithril 引导的全节点（writeShellApplication 脚本体）

NETWORK="${1:?usage: ef-node-run <preview|preprod|mainnet>}"
STATE="${STATE_DIRECTORY:-/var/lib/echoforge/$NETWORK}"
RUN_DIR="${RUNTIME_DIRECTORY:-/run/echoforge}"
HOST="${EF_HOST:-127.0.0.1}"
PORT="${EF_PORT:-3001}"

# 网络配置取自 cardano-node 发布件自带的 share/<network>/（由 mithril.nix 经
# EF_NODE_SHARE 注入）。以前是运行期从 book.world.dev.cardano.org 抓「最新」，
# 但网页配置永远跟着最新节点版本走，和被钉住的二进制迟早对不上 ——
# 10.1.4 配上 11.x 的配置就会死在
#   Parsing of backend config failed. Unknown config: "PrometheusSimple suffix ..."
# 同包发布保证版本一致，顺带让节点启动不再依赖网络（对 depin 断电自愈有意义）。
CFG_DIR="${EF_NODE_SHARE:?EF_NODE_SHARE not set (see modules/cardano/mithril.nix)}/$NETWORK"

if [ ! -s "$CFG_DIR/config.json" ]; then
  echo "==> no bundled config for network '$NETWORK' at $CFG_DIR" >&2
  echo "    available networks:" >&2
  find "$EF_NODE_SHARE" -mindepth 1 -maxdepth 1 -type d -printf '      %f\n' >&2 || true
  exit 1
fi

# 自有拓扑（Nix 生成，出块节点/中继必备）优先；未声明 localRoots 时
# 沿用发布件自带的公共拓扑（仅适合观察节点）。
TOPOLOGY="${EF_TOPOLOGY:-$CFG_DIR/topology.json}"
[ -r "$TOPOLOGY" ] || {
  echo "==> topology not readable: $TOPOLOGY" >&2
  exit 1
}

# 供 Ogmios / Kupo 读取的统一节点配置入口。
# 注意：它们把配置里的相对创世路径按**软链自己所在的目录**解析（而不是软链目标的
# 目录），所以四份创世必须一并链进 $RUN_DIR，否则索引层启动即
#   Yaml file not found: /run/echoforge/byron-genesis.json
# cardano-node 本身不受影响 —— 它按命令行传入的真实 --config 路径解析。
# shelley-genesis 另有一个用途：ef-cli pool 子命令按网络算 KES period 要读它。
ln -sf "$CFG_DIR/config.json" "$RUN_DIR/node-config.json"
for g in byron shelley alonzo conway; do
  ln -sf "$CFG_DIR/$g-genesis.json" "$RUN_DIR/$g-genesis.json"
done

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
