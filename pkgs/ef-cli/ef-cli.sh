# ef-cli — EchoForge 动态节点引擎 CLI（writeShellApplication 脚本体）
#
#   ef-cli node start --mode devnet            拉起本地极简私有链（~200MB）
#   ef-cli node start --mode mithril [--network preview|preprod|mainnet]
#   ef-cli node stop                           释放所有节点内存与 CPU 资源
#   ef-cli node status [--waybar]              查询状态（--waybar 输出状态栏 JSON）
#   ef-cli pool status [--network N] [--json]  出块节点 / KES 周期状态
#   ef-cli pool rotate-kes [--network N]       生成新 KES 密钥对并给出离线重签步骤
#   ef-cli profile switch <desktop|dev|spo|depin>
#   ef-cli version                             版本 / Profile / 构建修订
#
# 彩蛋层（球标、回声、纪念日等）在 eggs.sh，构建时前置拼接；main() 的兜底分支交给 egg_dispatch。

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
  ef-cli version
EOF
  anniversary_footer
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
  local mode="" network="preview" rc=0
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
      snapshot_socket ef-devnet.service
      sudo systemctl start ef-devnet.service
      # 返回码：0 = socket 已就绪；1 = 还在忙（单元仍活着）；2 = 单元已死
      rc=0; wait_for_echo ef-devnet.service || rc=$?
      if [ "$rc" = 2 ]; then
        # 单元真的死了：别再拉索引层（只会跟着空转重启），也别谎报成功
        sudo systemctl stop ef-devnet.service 2> /dev/null || true
        die "devnet 未能启动，已停止以免重启风暴；日志: journalctl -u ef-devnet -n 50"
      fi
      start_indexers_if_present
      if [ "$rc" = 1 ]; then
        echo "==> Devnet 仍在启动中（单元存活）。socket 就绪后即可使用。"
      else
        echo "==> Devnet up. Socket: /run/echoforge/node.socket"
      fi
      ;;
    mithril)
      case " $NETWORKS " in
        *" $network "*) ;;
        *) die "--network must be one of: $NETWORKS" ;;
      esac
      unit_exists "ef-node@.service" \
        || die "当前 Profile 未启用 mithril 节点模块，请先: ef-cli profile switch spo"
      echo "==> Mithril snapshot sync for $network (skips if DB exists)"
      network_epoch_aside "$network"
      sudo systemctl start "ef-mithril-sync@$network.service"
      echo "==> Starting $network node"
      snapshot_socket "ef-node@$network.service"
      sudo systemctl start "ef-node@$network.service"
      rc=0; wait_for_echo "ef-node@$network.service" || rc=$?
      if [ "$rc" = 2 ]; then
        sudo systemctl stop "ef-node@$network.service" 2> /dev/null || true
        die "$network 节点未能启动，已停止；日志: journalctl -u ef-node@$network -n 50"
      fi
      if [ "$rc" = 1 ]; then
        # 快照不含账本状态时，节点要从创世重放才开 socket —— 让它继续跑，
        # 索引层等 socket 出现后再拉（它们连不上会自行重启等待）。
        echo "==> $network 节点仍在启动中：Mithril 快照不含账本状态，正在从创世重放。"
        echo "    进度: journalctl -fu ef-node@$network | grep LedgerReplay"
        echo "    socket 就绪后再执行: ef-cli node start --mode mithril --network $network"
      else
        start_indexers_if_present
        echo "==> Node up. Socket: /run/echoforge/node.socket"
      fi
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
  echo "    ○ chain at rest · db kept in /var/lib/echoforge"
}

node_state() {
  # 输出: "devnet" | "<network>" | "sync" | "off"
  # 一次 systemctl 调用推导全部状态（Waybar 每 3 秒轮询一次，这里必须便宜）；
  # 无 systemctl 的工作站（macOS）→ off。
  # 列：UNIT LOAD ACTIVE SUB …。节点单元只认 ACTIVE=active（崩溃重启窗口的 activating/auto-restart 不算运行）；
  # oneshot 的 ef-mithril-sync@ 运行中是 activating/start → sync。
  local units u _load active sub _rest sync=0
  units="$(systemctl list-units --plain --no-legend --state=active,activating 'ef-*.service' 2> /dev/null || true)"
  while read -r u _load active sub _rest; do
    case "$u" in
      ef-devnet.service)
        if [ "$active" = "active" ]; then
          echo "devnet"
          return
        fi
        ;;
      ef-node@*.service)
        # 只认白名单里的实例名（单元名转义如 \x2d 不能原样进 Waybar JSON）
        if [ "$active" = "active" ]; then
          u="${u#ef-node@}"
          u="${u%.service}"
          case " $NETWORKS " in
            *" $u "*)
              echo "$u"
              return
              ;;
          esac
        fi
        ;;
      ef-mithril-sync@*.service)
        if [ "$sub" = "start" ]; then sync=1; fi
        ;;
    esac
  done <<< "$units"
  if [ "$sync" = 1 ]; then echo "sync"; else echo "off"; fi
}

cmd_node_status() {
  local waybar=0 state suffix='' glyph ogmios=0
  case "${1:-}" in
    --waybar) waybar=1 ;;
    --breathe)
      cmd_node_breathe
      return
      ;;
  esac
  state="$(node_state)"

  if [ "$waybar" = 1 ]; then
    # 状态栏呼吸灯协定：off=灰色熄灭，devnet/mithril=高亮白呼吸，sync=灰色呼吸（样式见 Waybar CSS）
    # 纪念日只改 tooltip（text/class 不动，CSS 契约不受影响）；is_anniversary 为内建判定，零 fork
    if is_anniversary; then
      suffix=" · GENESIS DAY · YEAR $(genesis_year)"
    fi
    case "$state" in
      off)
        printf '{"text":"●","class":"off","tooltip":"EchoForge Node · OFF%s"}\n' "$suffix"
        ;;
      devnet)
        printf '{"text":"●","class":"devnet","tooltip":"EchoForge Node · Local Devnet%s"}\n' "$suffix"
        ;;
      sync)
        printf '{"text":"●","class":"sync","tooltip":"EchoForge Node · Mithril Sync%s"}\n' "$suffix"
        ;;
      *)
        printf '{"text":"●","class":"mithril","tooltip":"EchoForge Node · %s (mithril)%s"}\n' "$state" "$suffix"
        ;;
    esac
    return
  fi

  # 首行字形 = Waybar 上那颗点：○ 熄灭 / ◐ 快照恢复中 / ● 运行
  case "$state" in
    off) glyph='○' ;;
    sync) glyph='◐' ;;
    *) glyph='●' ;;
  esac
  if [ "$state" = "off" ] && [ "$(current_profile)" = "desktop" ]; then
    echo "$glyph EchoForge node state: off · 0 MB / 0 % as promised"
  else
    echo "$glyph EchoForge node state: $state"
  fi
  if [ "$state" != "off" ] && [ "$state" != "sync" ]; then
    echo "  socket : /run/echoforge/node.socket"
    if [ -S "$SOCKET" ]; then
      echo "  echo   : ● received"
    else
      echo "  echo   : ◐ pending"
    fi
    if is_active ef-ogmios.service; then
      echo "  ogmios : ws://127.0.0.1:1337"
      ogmios=1
    fi
    if is_active ef-kupo.service; then
      echo "  kupo   : http://127.0.0.1:1442"
    fi
    # 同步球：只在 Ogmios 活跃时向 127.0.0.1:1337/health 发一次环回 GET（永不进 --waybar 路径）
    if [ "$ogmios" = 1 ]; then
      render_sync_sphere
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
    sync) die "Mithril 快照恢复中，节点尚未运行 —— 等同步完成后再试" ;;
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

# 操作证书路径：先问 systemd 单元真正在用哪个，而不是猜。
# echoforge.node.mithril.blockProducer.opCertFile 是可配置的（模块只对落在
# /run/secrets/ 下的路径自动声明 sops 条目，指别处就不走 sops），
# 硬编码默认值会让 CLI 与节点各说各话，然后静默误报「producer 关闭」。
# 优先级：显式 EF_OP_CERT > 单元环境里的 EF_OP_CERT > 默认路径。
resolve_opcert() {
  local network="$1" from_unit
  if [ -n "${EF_OP_CERT:-}" ]; then
    echo "$EF_OP_CERT"
    return 0
  fi
  from_unit="$(
    systemctl show "ef-node@$network.service" -p Environment --value 2> /dev/null \
      | tr ' ' '\n' | sed -n 's/^EF_OP_CERT=//p' | head -n1
  )"
  echo "${from_unit:-$DEFAULT_OP_CERT}"
}

# kes-period-info.json 是公开的证书元数据（周期区间、链上/本地计数器），
# 不是秘密 —— 没必要和 KES 私钥挤在同一个 tmpfs 里。实测踩过：桌面会话把
# XDG_RUNTIME_DIR 写满之后，连这个只读查询都会 ENOSPC 失败。
query_work_dir() {
  local dir
  dir="$(mktemp -d -t ef-pool-query.XXXXXX)"
  echo "$dir"
}

# 每次调用都落在 tmpfs（XDG_RUNTIME_DIR，内存挂载）里 —— KES 私钥绝不落盘。
# 仅 rotate-kes 使用；只读查询请用 query_work_dir。
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
  opcert="$(resolve_opcert "$network")"
  state="$(node_state)"

  if [ "$as_json" = 0 ]; then
    echo "EchoForge pool status ($network)"
    echo "  node    : $state"
    echo "  socket  : $SOCKET"
  fi

  # 单元环境里有 EF_OP_CERT 就说明 blockProducer 已启用 —— 这时证书读不到
  # 是真故障（sops 没解开 / 属主或模式不对），和「这是台中继」是两回事，
  # 给同一句提示会把人带偏。
  bp_enabled=0
  if systemctl show "ef-node@$network.service" -p Environment --value 2> /dev/null \
    | grep -q 'EF_OP_CERT='; then
    bp_enabled=1
  fi

  if [ ! -r "$opcert" ]; then
    if [ "$as_json" = 1 ]; then
      die "operational certificate 不可读: $opcert"
    fi
    if [ "$bp_enabled" = 1 ]; then
      echo "  producer: 已启用，但证书读不到 —— $opcert"
      echo
      echo "节点单元声明的出块证书当前不可读。常见原因："
      echo "  · sops 没解开：ls -l /run/secrets/pool/ ；journalctl -u sops-install-secrets"
      echo "  · 属主/模式不对：应为 owner=cardano，node.cert 为 0440"
      echo "  · 你不在 cardano 组：id -nG（组变更需重新登录才生效）"
    else
      echo "  producer: 关闭（未声明出块证书）"
      echo
      echo "中继节点不需要操作证书。要转为出块节点："
      echo "  1. profiles/spo.nix 取消注释 mithril.blockProducer.enable = true;"
      echo "  2. 按 secrets/README.md 把 KES/VRF/OpCert 放进 sops"
      echo "  3. nixos-rebuild switch 后重启节点"
    fi
    return 0
  fi

  work="$(query_work_dir)"
  # kes-period-info 会把人类可读诊断打到 stdout，JSON 单独写文件，两者分开取
  if ! info="$(cardano-cli query kes-period-info \
    --socket-path "$SOCKET" "${MAGIC_ARGS[@]}" \
    --op-cert-file "$opcert" \
    --out-file "$work/kes-period-info.json" 2>&1)"; then
    echo "$info" >&2
    # 不要替 cardano-cli 猜原因 —— 上面已经把它的原文打出来了。
    # 只对一个实测踩过的坑给出定向提示：ENOSPC 未必是磁盘满。$work 落在 /tmp，
    # 而 depin 的根就是 tmpfs（内存），那里的 ENOSPC 其实是内存不够 ——
    # 节点在链尖能占 3 GB 以上。所以不猜，直接把挂载点用量摆出来。
    case "$info" in
      *"No space left on device"*)
        echo "  写入 $work 失败：ENOSPC。该挂载点当前用量：" >&2
        df -h "$work" >&2 || true
        die "先腾出空间再重试"
        ;;
      *)
        die "查询 KES 周期失败，原因见上方 cardano-cli 输出"
        ;;
    esac
  fi

  if [ "$as_json" = 1 ]; then
    cat "$work/kes-period-info.json"
    rm -rf "$work"
    return 0
  fi

  echo "  opcert  : $opcert"
  jq -r '
    "  KES 周期: 当前 \(.qKesCurrentKesPeriod // "?")，证书有效区间 [\(.qKesStartKesInterval // "?"), \(.qKesEndKesInterval // "?"))",
    "  剩余    : \((.qKesEndKesInterval // 0) - (.qKesCurrentKesPeriod // 0)) 个周期，到期 \(.qKesKesKeyExpiry // "?")",
    "  计数器  : 链上 \(.qKesNodeStateOperationalCertificateNumber // "?") / 本地 \(.qKesOnDiskOperationalCertificateNumber // "?")"
  ' "$work/kes-period-info.json"
  rm -rf "$work"
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
      # 彩蛋层（eggs.sh）认识的词直接回答；其余仍是 usage + exit 1
      if ! egg_dispatch "$@"; then
        usage
        exit 1
      fi
      ;;
  esac
}

main "$@"
