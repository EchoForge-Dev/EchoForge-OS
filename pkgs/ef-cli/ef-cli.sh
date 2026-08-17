# ef-cli — EchoForge 动态节点引擎 CLI（writeShellApplication 脚本体）
#
#   ef-cli node start --mode devnet            拉起本地极简私有链（~200MB）
#   ef-cli node start --mode mithril [--network preview|preprod|mainnet]
#   ef-cli node stop                           释放所有节点内存与 CPU 资源
#   ef-cli node status [--waybar]              查询状态（--waybar 输出状态栏 JSON）
#   ef-cli pool status [--network N] [--json]  出块节点 / KES 周期状态
#   ef-cli pool rotate-kes [--network N]       生成新 KES 密钥对并给出离线重签步骤
#   ef-cli profile switch <desktop|dev|spo|depin>

NETWORKS="preview preprod mainnet"
SOCKET="/run/echoforge/node.socket"
DEFAULT_OP_CERT="/run/secrets/pool/node.cert"
MAGIC_ARGS=()

flake_ref() {
  if [ -n "${EF_FLAKE:-}" ]; then
    echo "$EF_FLAKE"
  elif [ -r /etc/echoforge/flake.ref ]; then
    cat /etc/echoforge/flake.ref
  else
    echo "github:EchoForge-Dev/EchoForge-OS"
  fi
}

usage() {
  cat <<'EOF'
ef-cli — EchoForge OS node & profile manager

USAGE:
  ef-cli node start --mode devnet
  ef-cli node start --mode mithril [--network preview|preprod|mainnet]
  ef-cli node stop
  ef-cli node status [--waybar]
  ef-cli pool status [--network preview|preprod|mainnet] [--json]
  ef-cli pool rotate-kes [--network preview|preprod|mainnet] [--force]
  ef-cli profile switch <desktop|dev|spo|depin>
EOF
}

die() {
  echo "ef-cli: $*" >&2
  exit 1
}

unit_exists() {
  systemctl cat "$1" > /dev/null 2>&1
}

is_active() {
  [ "$(systemctl is-active "$1" 2> /dev/null || true)" = "active" ]
}

start_indexers_if_present() {
  if unit_exists ef-ogmios.service; then
    sudo systemctl start ef-ogmios.service ef-kupo.service
    echo "    Ogmios  ws://127.0.0.1:1337"
    echo "    Kupo    http://127.0.0.1:1442"
  fi
}

cmd_node_start() {
  local mode="" network="preview"
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --network) network="${2:-}"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  case "$mode" in
    devnet)
      unit_exists ef-devnet.service \
        || die "当前 Profile 未启用 devnet 模块，请先: ef-cli profile switch dev"
      echo "==> Starting local devnet (~200MB, second-level blocks)"
      sudo systemctl start ef-devnet.service
      start_indexers_if_present
      echo "==> Devnet up. Socket: /run/echoforge/node.socket"
      ;;
    mithril)
      case " $NETWORKS " in
        *" $network "*) ;;
        *) die "--network must be one of: $NETWORKS" ;;
      esac
      unit_exists "ef-node@.service" \
        || die "当前 Profile 未启用 mithril 节点模块，请先: ef-cli profile switch spo"
      echo "==> Mithril snapshot sync for $network (skips if DB exists)"
      sudo systemctl start "ef-mithril-sync@$network.service"
      echo "==> Starting $network node"
      sudo systemctl start "ef-node@$network.service"
      start_indexers_if_present
      echo "==> Node up. Socket: /run/echoforge/node.socket"
      ;;
    *)
      die "--mode must be devnet or mithril"
      ;;
  esac
}

cmd_node_stop() {
  echo "==> Stopping all EchoForge node services"
  sudo systemctl stop "ef-node@*.service" 2> /dev/null || true
  for unit in ef-devnet ef-ogmios ef-kupo; do
    if unit_exists "$unit.service"; then
      sudo systemctl stop "$unit.service" 2> /dev/null || true
    fi
  done
  echo "==> All node memory/CPU released"
}

node_state() {
  # 输出: "devnet" | "<network>" | "off"
  if is_active ef-devnet.service; then
    echo "devnet"
    return
  fi
  for network in $NETWORKS; do
    if is_active "ef-node@$network.service"; then
      echo "$network"
      return
    fi
  done
  echo "off"
}

cmd_node_status() {
  local waybar=0 state
  if [ "${1:-}" = "--waybar" ]; then
    waybar=1
  fi
  state="$(node_state)"

  if [ "$waybar" = 1 ]; then
    # 状态栏呼吸灯协定：off=灰色熄灭，devnet/mithril=高亮白呼吸（样式见 Waybar CSS）
    case "$state" in
      off)
        printf '{"text":"●","class":"off","tooltip":"EchoForge Node · OFF"}\n'
        ;;
      devnet)
        printf '{"text":"●","class":"devnet","tooltip":"EchoForge Node · Local Devnet"}\n'
        ;;
      *)
        printf '{"text":"●","class":"mithril","tooltip":"EchoForge Node · %s (mithril)"}\n' "$state"
        ;;
    esac
    return
  fi

  echo "EchoForge node state: $state"
  if [ "$state" != "off" ]; then
    echo "  socket : /run/echoforge/node.socket"
    if is_active ef-ogmios.service; then
      echo "  ogmios : ws://127.0.0.1:1337"
    fi
    if is_active ef-kupo.service; then
      echo "  kupo   : http://127.0.0.1:1442"
    fi
  fi
}

# ---------------------------------------------------------------- pool（SPO）

set_magic_args() {
  case "$1" in
    mainnet) MAGIC_ARGS=(--mainnet) ;;
    preprod) MAGIC_ARGS=(--testnet-magic 1) ;;
    preview) MAGIC_ARGS=(--testnet-magic 2) ;;
    *) die "unknown network: $1（可选：$NETWORKS）" ;;
  esac
}

# 未显式指定 --network 时取当前运行中的网络
resolve_network() {
  local network="$1" state
  if [ -n "$network" ]; then
    case " $NETWORKS " in
      *" $network "*) echo "$network"; return 0 ;;
      *) die "--network must be one of: $NETWORKS" ;;
    esac
  fi
  state="$(node_state)"
  case "$state" in
    off) die "节点未运行 —— 先 ef-cli node start --mode mithril --network <$NETWORKS>，或显式传 --network" ;;
    devnet) die "当前运行的是本地 devnet，pool 子命令只适用于 mithril 节点" ;;
  esac
  echo "$state"
}

shelley_genesis() {
  local network="$1" candidate
  for candidate in \
    /run/echoforge/shelley-genesis.json \
    "/var/lib/echoforge/$network/config/shelley-genesis.json"; do
    if [ -r "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# 每次调用都落在 tmpfs（XDG_RUNTIME_DIR，内存挂载）里 —— KES 私钥绝不落盘
pool_work_dir() {
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ef-pool-rotate"
  mkdir -p "$dir"
  chmod 700 "$dir"
  echo "$dir"
}

cmd_pool_status() {
  local network="" as_json=0 opcert state work info
  while [ $# -gt 0 ]; do
    case "$1" in
      --network) network="${2:-}"; shift 2 ;;
      --json) as_json=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  unit_exists "ef-node@.service" \
    || die "当前 Profile 未启用 mithril 节点模块，请先: ef-cli profile switch spo"

  network="$(resolve_network "$network")"
  set_magic_args "$network"
  opcert="${EF_OP_CERT:-$DEFAULT_OP_CERT}"
  state="$(node_state)"

  if [ "$as_json" = 0 ]; then
    echo "EchoForge pool status ($network)"
    echo "  node    : $state"
    echo "  socket  : $SOCKET"
  fi

  if [ ! -r "$opcert" ]; then
    if [ "$as_json" = 1 ]; then
      die "operational certificate 不可读: $opcert"
    fi
    echo "  producer: 关闭（$opcert 不可读）"
    echo
    echo "中继节点不需要操作证书。要转为出块节点："
    echo "  1. profiles/spo.nix 取消注释 mithril.blockProducer.enable = true;"
    echo "  2. 按 secrets/README.md 把 KES/VRF/OpCert 放进 sops"
    echo "  3. nixos-rebuild switch 后重启节点"
    return 0
  fi

  work="$(pool_work_dir)"
  # kes-period-info 会把人类可读诊断打到 stdout，JSON 单独写文件，两者分开取
  if ! info="$(cardano-cli query kes-period-info \
    --socket-path "$SOCKET" "${MAGIC_ARGS[@]}" \
    --op-cert-file "$opcert" \
    --out-file "$work/kes-period-info.json" 2>&1)"; then
    echo "$info" >&2
    die "查询 KES 周期失败（节点是否已完成同步？）"
  fi

  if [ "$as_json" = 1 ]; then
    cat "$work/kes-period-info.json"
    return 0
  fi

  echo "  opcert  : $opcert"
  jq -r '
    "  KES 周期: 当前 \(.qKesCurrentKesPeriod // "?")，证书有效区间 [\(.qKesStartKesInterval // "?"), \(.qKesEndKesInterval // "?"))",
    "  剩余    : \((.qKesEndKesInterval // 0) - (.qKesCurrentKesPeriod // 0)) 个周期，到期 \(.qKesKesKeyExpiry // "?")",
    "  计数器  : 链上 \(.qKesNodeStateOperationalCertificateNumber // "?") / 本地 \(.qKesOnDiskOperationalCertificateNumber // "?")"
  ' "$work/kes-period-info.json"
  echo
  echo "$info"
}

cmd_pool_rotate_kes() {
  local network="" force=0 work genesis slot slots_per_period period
  while [ $# -gt 0 ]; do
    case "$1" in
      --network) network="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  network="$(resolve_network "$network")"
  set_magic_args "$network"

  work="$(pool_work_dir)"
  if [ -e "$work/kes.skey" ] && [ "$force" = 0 ]; then
    die "$work/kes.skey 已存在 —— 确认已 sops 收录后删除，或加 --force 覆盖"
  fi

  genesis="$(shelley_genesis "$network")" \
    || die "找不到 $network 的 shelley-genesis.json —— 请先启动一次节点让它拉齐网络配置"

  slot="$(cardano-cli query tip --socket-path "$SOCKET" "${MAGIC_ARGS[@]}" | jq -r '.slot')"
  slots_per_period="$(jq -r '.slotsPerKESPeriod' "$genesis")"
  period=$((slot / slots_per_period))

  echo "==> 生成新 KES 密钥对（$work，tmpfs 内存挂载，重启即消失）"
  cardano-cli node key-gen-KES \
    --verification-key-file "$work/kes.vkey" \
    --signing-key-file "$work/kes.skey"

  cat <<EOF

当前 KES period : $period（slot $slot / 每周期 $slots_per_period slots）

冷密钥不在本机 —— 剩下两步必须在离线签名机上完成：

  1. 把 $work/kes.vkey 拷到离线机，用冷密钥重签操作证书：

       cardano-cli node issue-op-cert \\
         --kes-verification-key-file kes.vkey \\
         --cold-signing-key-file cold.skey \\
         --operational-certificate-issue-counter-file cold.counter \\
         --kes-period $period \\
         --out-file node.cert

  2. 把新的 node.cert 拷回本机，与 $work/kes.skey 一起写进 sops：

       nix develop -c sops secrets/secrets.yaml     # 更新 pool/kes.skey 与 pool/node.cert
       sudo nixos-rebuild switch --flake .#echoforge-spo
       ef-cli node stop && ef-cli node start --mode mithril --network $network

收尾：确认 ef-cli pool status 的链上计数器已经追上本地计数器后，
执行 rm -rf $work 清掉内存里的明文 KES 私钥。
EOF
}

cmd_profile_switch() {
  local target="${1:-}"
  case "$target" in
    desktop | dev | spo | depin) ;;
    *) die "usage: ef-cli profile switch <desktop|dev|spo|depin>" ;;
  esac
  local flake
  flake="$(flake_ref)"
  echo "==> Rebuilding system as echoforge-$target from $flake"
  exec sudo nixos-rebuild switch --flake "$flake#echoforge-$target"
}

main() {
  case "${1:-}" in
    node)
      shift
      case "${1:-}" in
        start) shift; cmd_node_start "$@" ;;
        stop) shift; cmd_node_stop ;;
        status) shift; cmd_node_status "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    pool)
      shift
      case "${1:-}" in
        status) shift; cmd_pool_status "$@" ;;
        rotate-kes) shift; cmd_pool_rotate_kes "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    profile)
      shift
      case "${1:-}" in
        switch) shift; cmd_profile_switch "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    -h | --help | help | "")
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
