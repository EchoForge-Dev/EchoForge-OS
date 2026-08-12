# ef-cli — EchoForge 动态节点引擎 CLI（writeShellApplication 脚本体）
#
#   ef-cli node start --mode devnet            拉起本地极简私有链（~200MB）
#   ef-cli node start --mode mithril [--network preview|preprod|mainnet]
#   ef-cli node stop                           释放所有节点内存与 CPU 资源
#   ef-cli node status [--waybar]              查询状态（--waybar 输出状态栏 JSON）
#   ef-cli profile switch <desktop|dev|spo|depin>

NETWORKS="preview preprod mainnet"

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
