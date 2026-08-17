# ef-cli 彩蛋层（eggs.sh）—— 与 ef-cli.sh 前置拼接为同一个 writeShellApplication 脚本体
#
# 约束（与 CLAUDE.MD §4 / EFDS 一致）：
#   · 纯 stdout、无特权、无 secrets 读取；唯一的"网络"是 render_sync_sphere 对
#     127.0.0.1:1337 (Ogmios /health) 的一次手动环回 GET，且仅当 ef-ogmios 活跃时
#   · shellcheck-clean；macOS 工作站可跑（bash 5 内建，绝不用 date -d）
#   · `==>` 主提示行逐字节不变；动效只表状态；单色 + 四态字形 ● ◐ ◌ ○ 只表状态
#   · Waybar 3 秒轮询路径上只允许 bash 内建（零 fork）
#   · $SOCKET 复用 ef-cli.sh 顶部已声明的常量（不重复定义 socket 路径）

EF_GENESIS=1775865600 # 2026-04-11T00:00:00Z —— EchoForge 成立
EF_EPOCH_LEN=432000   # 5 天，同 mainnet

# mark-tiny：命令行化的 EchoForge 球标（11×4，纯 ASCII，4 行 = 四 Profile 各点亮一条）
SPHERE=(
  '  _.-~~-._'
  ' .__.-~~-._'
  ' ~-.__.-~~-'
  '  ~-.__.-~'
)
# 4 条波带自上而下绑定四 Profile（ef-cli version 点亮当前那条）
PROFILES=(desktop dev spo depin)

is_tty() { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }
motion_ok() { is_tty && [ -z "${EF_REDUCED_MOTION:-}" ]; }

# 256 色 244 = #808080（--text-secondary / --echo-gray，EFDS 唯一的"次要"灰）
gray() {
  if is_tty; then
    printf '\033[38;5;244m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

# EFDS 宽字距大写标签：tracked 'echoforge os' → "E C H O F O R G E   O S"
tracked() {
  local s="${1^^}" o='' i
  for ((i = 0; i < ${#s}; i++)); do
    o+="${s:i:1} "
  done
  printf '  %s\n' "${o% }"
}

now_s() { echo "${EPOCHSECONDS:-$(date +%s)}"; }

current_profile() {
  local p=workstation
  if [ -r /etc/echoforge/profile ]; then
    read -r p < /etc/echoforge/profile || true # 文件无尾随换行 → read 返回 1
  fi
  echo "$p"
}

motto_line() {
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    zh*) echo '一切为简' ;;
    *) echo 'ALL FOR SIMPLE' ;;
  esac
}

# 纪念日判定：printf %()T 是 bash 内建 → 零 fork（Waybar 轮询路径可用）
is_anniversary() {
  local md
  printf -v md '%(%m-%d)T' -1
  [ "$md" = 04-11 ] || [ -n "${EF_ANNIVERSARY:-}" ]
}
genesis_year() {
  local y
  printf -v y '%(%Y)T' -1
  echo $((10#$y - 2026))
}
anniversary_footer() {
  if is_anniversary; then
    echo
    gray "  GENESIS DAY · YEAR $(genesis_year) · est. 2026-04-11"
  fi
}

# ── ef-cli version / logo ────────────────────────────────────────────────
cmd_version() {
  local p i now days epoch legend='' variant='' rev=''
  p="$(current_profile)"
  now="$(now_s)"
  days=$(((now - EF_GENESIS) / 86400))
  epoch=$(((now - EF_GENESIS) / EF_EPOCH_LEN))
  for i in 0 1 2 3; do
    if [ "$p" = workstation ] || [ "${PROFILES[i]}" = "$p" ]; then
      printf '  %s\n' "${SPHERE[i]}"
    else
      gray "  ${SPHERE[i]}"
    fi
  done
  echo
  tracked 'echoforge os'
  printf '  %-9s %s\n' PROFILE "$p"
  if [ -r /etc/os-release ]; then
    # 解析而非 source（不把配置文件当 shell 执行）
    variant=$(sed -n 's/^VARIANT="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release)
  fi
  if [ -n "$variant" ]; then
    printf '  %-9s EchoForge OS · %s\n' SYSTEM "$variant"
  fi
  if command -v nixos-version > /dev/null 2>&1; then
    rev=$(nixos-version --configuration-revision 2> /dev/null || true)
  fi
  if [ -n "$rev" ]; then
    printf '  %-9s %s\n' REV "${rev:0:7}"
  fi
  printf '  %-9s %s · DAY %s   since 2026-04-11\n' EPOCH "$epoch" "$days"
  printf '  %-9s %s\n' FLAKE "$(flake_ref)"
  for i in 0 1 2 3; do
    if [ "${PROFILES[i]}" = "$p" ]; then
      legend+="● ${PROFILES[i]}  "
    else
      legend+="○ ${PROFILES[i]}  "
    fi
  done
  printf '  %s\n' "${legend%  }"
  echo '  一切为简 / All for Simple · echoforgellc.tech'
  anniversary_footer
}

cmd_logo() {
  if [ "${1:-}" = --tiny ]; then
    printf '  %s\n' "${SPHERE[@]}"
    return
  fi
  # 68 列横幅：mark-medium（30 列，仅 ▀▄█）+ ECHOFORGE 3×5 像素字 + 宽字距标语
  cat <<'EOF'
        ▄▄▄▄▄▄▄
      ▀▀▀▀▀▀██████▄▄▄▄▄▄▄
   ▄▄▄▄▄▄▄▄▄   ▀▀▀████████▄
 ▄█████████████▄▄▄         ▄▄    ███  ██ █ █  █  ███  █  ██   ██ ███
 ▀▀         ▀▀▀██████████████    █   █   █ █ █ █ █   █ █ █ █ █   █
▄▄▄█████████▄▄▄   ▀▀▀▀▀▀▀▀▀      ██  █   ███ █ █ ██  █ █ ██  █ █ ██
███▀▀▀▀▀▀▀▀▀██████▄▄▄▄▄▄▄▄▄███   █   █   █ █ █ █ █   █ █ █ █ █ █ █
   ▄▄▄▄▄▄▄▄▄   ▀▀▀█████████▀▀▀   ███  ██ █ █  █  █    █  █ █  ██ ███
 ██████████████▄▄▄         ▄▄
 ▀▀         ▀▀▀█████████████▀        A L L   F O R   S I M P L E
   ▀████████▄▄▄   ▀▀▀▀▀▀▀▀▀
     ▀▀▀▀▀▀▀██████▄▄▄▄▄▄
               ▀▀▀▀▀▀▀
EOF
}

# ── ef-cli echo：真正的回声 —— 逐次变短、变暗；连喊三声，球出现 ────────────
cmd_echo() {
  local text clean len i keep
  local glyphs=('●' '◐' '◌' '○') levels=(231 250 244 238) # 白 → #c0c0c0 → #808080 → #404040
  # `ef-cli echo echo echo`：子命令本身已是第一声，这里再收到两声 → 三声召唤，球自己出现，不需要台词
  if [ $# -eq 2 ] && [ "${1,,}" = echo ] && [ "${2,,}" = echo ]; then
    cmd_version
    return
  fi
  text="$*"
  [ -n "$text" ] || text='一切为简 / All for Simple'
  # 剥掉控制字符（纯 bash、零 fork：UTF-8 locale 下 [[:cntrl:]] 覆盖 C0 / DEL / C1，含 U+009B CSI）；
  # 用户文本之后只作 printf 的 %s 参数
  clean="${text//[[:cntrl:]]/}"
  len=${#clean}
  for i in 0 1 2 3; do
    keep=$((len * (4 - i) / 4))
    [ "$keep" -ge 1 ] || keep=1
    if is_tty; then
      printf '\033[38;5;%sm%s %s\033[0m\n' "${levels[i]}" "${glyphs[i]}" "${clean:0:keep}"
    else
      printf '%s %s\n' "${glyphs[i]}" "${clean:0:keep}"
    fi
    if [ "$i" -lt 3 ] && motion_ok; then sleep 0.2; fi
  done
}

# ── ef-cli genesis：EchoForge 链时（成立日 = epoch 0，5 天一个 epoch）───────
# 公开链参数（离线估算用，全部标注 offline）：
#   mainnet  Shelley 起点 slot 4492800 @ 1596059091（epoch 208）；Byron/Shelley epoch 均 432000 s → 线性
#   preprod  系统起点 1654041600，epoch 432000 s
#   preview  系统起点 1666656000，epoch 86400 s
chain_epoch() { # $1 = mainnet|preprod|preview  $2 = unix 秒 → 打印该时刻的（估算）epoch
  case "$1" in
    mainnet) echo $((208 + ($2 - 1596059091) / 432000)) ;;
    preprod) echo $((($2 - 1654041600) / 432000)) ;;
    preview) echo $((($2 - 1666656000) / 86400)) ;;
    *) echo '-' ;;
  esac
}

cmd_genesis() {
  local now days epoch slot day_in bar='' i
  now="$(now_s)"
  if [ "$now" -lt "$EF_GENESIS" ]; then
    die "clock is before genesis (2026-04-11) — check the RTC"
  fi
  days=$(((now - EF_GENESIS) / 86400))
  epoch=$(((now - EF_GENESIS) / EF_EPOCH_LEN))
  slot=$(((now - EF_GENESIS) % EF_EPOCH_LEN))
  day_in=$((days % 5 + 1))
  for i in 1 2 3 4 5; do
    if [ "$i" -le "$day_in" ]; then bar+='▓'; else bar+='░'; fi
  done
  tracked 'echoforge genesis'
  printf '  %-14s %s\n' 'SYSTEM START' "2026-04-11T00:00:00Z   ($EF_GENESIS)"
  printf '  %-14s %s\n' 'EPOCH LENGTH' "$EF_EPOCH_LEN s · 5 days · same as mainnet"
  printf '  %-14s %s\n' 'SLOT LENGTH' '1 s'
  printf '  %-14s %s\n' NOW "EPOCH $epoch · SLOT $slot · DAY $day_in/5   $bar"
  printf '  %-14s %s\n' MAINNET "forged in EPOCH $(chain_epoch mainnet "$EF_GENESIS") · absolute slot $((4492800 + EF_GENESIS - 1596059091)) · now ≈ EPOCH $(chain_epoch mainnet "$now") (offline arithmetic)"
  printf '  %-14s %s\n' PREPROD "forged in EPOCH $(chain_epoch preprod "$EF_GENESIS") · now ≈ $(chain_epoch preprod "$now")"
  printf '  %-14s %s\n' PREVIEW "forged in EPOCH $(chain_epoch preview "$EF_GENESIS") · now ≈ $(chain_epoch preview "$now")"
  printf '  %-14s %s\n' BANDS 'BYRON · SHELLEY · GOGUEN · BASHO · VOLTAIRE   (five bands, five eras)'
  printf '  %-14s %s\n' MOTTO 'ALL FOR SIMPLE'
  if is_anniversary; then
    echo
    tracked "genesis day · year $(genesis_year)"
  fi
}

# node start --mode mithril 的一句离线旁白（`==>` 行不动）
network_epoch_aside() { # $1 = network
  local now
  now="$(now_s)"
  printf '    %s ≈ epoch %s (offline estimate) · EchoForge genesis: epoch %s\n' \
    "$1" "$(chain_epoch "$1" "$now")" "$(chain_epoch "$1" "$EF_GENESIS")"
}

# ── Stickman Charles：头是节点状态点 ────────────────────────────────────
cmd_stickman() {
  local state head l1
  state="$(node_state)"
  if [ "$state" = off ]; then
    head='○' l1='node · OFF'
  else
    head='●' l1="node · $state"
  fi
  if is_anniversary; then
    printf '    \\%s/     %s\n' "$head" "$l1"
    printf '     |      %s\n' 'stickmancharles.com'
    printf '    / \\     %s\n' "GENESIS DAY · YEAR $(genesis_year)"
  else
    printf '     %s      %s\n' "$head" "$l1"
    printf '    /|\\     %s\n' 'stickmancharles.com'
    printf '    / \\     %s\n' 'echoforgellc.tech'
  fi
}

# ── 词典：有意义的"未知词"给出回答；其余交回 usage ────────────────────────
cmd_mantra() {
  # 按一年中的第几天确定性选取（无 RNG，同一天所有机器一致 —— 像 Nix 构建一样可复现）
  local d
  local lines=(
    'Nothing autostarts. Not even the node.'
    '127.0.0.1 is the only address a devnet needs.'
    'Secrets live in /run/secrets. Nowhere else.'
    'If it is not in flake.nix, it did not happen.'
    'One socket: /run/echoforge/node.socket.'
    'Gray is off. White is alive. That is the whole dashboard.'
    'Zero MB idle is a feature.'
    "Rebuild, don't repair."
  )
  printf -v d '%(%j)T' -1
  echo "${lines[$((10#$d % ${#lines[@]}))]}"
}

egg_dispatch() {
  local w="${1:-}"
  case "${w,,}" in
    version | --version | -v) cmd_version ;;
    logo)
      shift
      cmd_logo "$@"
      ;;
    echo)
      shift
      cmd_echo "$@"
      ;;
    genesis | epoch | 0411) cmd_genesis ;;
    stickman | charles | hi | hello | 你好) cmd_stickman ;;
    simple | all-for-simple) echo '一切为简' ;;
    一切为简) echo 'All for Simple' ;;
    mantra | motto) cmd_mantra ;;
    42) echo '42 · devnet testnet magic — local by default (127.0.0.1).' ;;
    secret | secrets | mnemonic | key | keys)
      echo 'Secrets live in /run/secrets and nowhere else. Not even here.'
      ;;
    sudo) echo 'NOPASSWD sudo is scoped to: systemctl start|stop|restart ef-* — everything else asks for your password.' ;;
    lovelace | ada) echo '1 ₳ = 1 000 000 lovelace · one epoch = 5 d = 432 000 slots.' ;;
    forge) echo 'Nothing autostarts. Not even the forge. → ef-cli node start --mode devnet' ;;
    *) return 1 ;;
  esac
}

# ── 节点生命周期的回声语义（由 ef-cli.sh 的 node 子命令调用）────────────────
# 等待第一声回声：节点开口 = socket 出现（最多 30 s）。
# RuntimeDirectoryPreserve=true 会留下上一轮的 socket 文件，所以在 start 之前先记下它的 inode+mtime，
# 只有"新的" socket 才算回声；单元中途失败则立刻说明，不空等。
socket_id() { # 仅在 Linux（systemctl 存在）路径上调用；stat 来自 GNU coreutils
  if [ -S "$SOCKET" ]; then stat -c '%i:%Y' "$SOCKET" 2> /dev/null || true; fi
}
EF_SOCK_BEFORE=''
snapshot_socket() { # $1 = unit —— 在 systemctl start 之前调用；节点本就在跑则记为 already
  if is_active "$1" && [ -S "$SOCKET" ]; then
    EF_SOCK_BEFORE=already
  else
    EF_SOCK_BEFORE="$(socket_id)"
  fi
}
wait_for_echo() { # $1 = unit（排障提示用）
  local i=0 now st
  if [ "$EF_SOCK_BEFORE" = already ]; then
    printf '    ● echo already received  %s\n' "$SOCKET"
    return 0
  fi
  printf '    ◐ waiting for first echo '
  while [ "$i" -lt 60 ]; do
    now="$(socket_id)"
    if [ -n "$now" ] && [ "$now" != "$EF_SOCK_BEFORE" ]; then
      printf '\n    ● echo received  %s\n' "$SOCKET"
      return 0
    fi
    st="$(systemctl is-active "$1" 2> /dev/null || true)"
    if [ "$st" != "active" ] && [ "$st" != "activating" ]; then
      printf '\n    ◌ %s is %s — journalctl -u %s\n' "$1" "${st:-gone}" "$1"
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
    printf '.'
  done
  printf '\n    ◌ no echo yet (still starting?) — journalctl -fu %s\n' "$1"
}

# 同步球：节点追赶链尖时 4 条波带逐条点亮（Ogmios /health，仅环回，仅手动 status）
render_sync_sphere() {
  command -v curl > /dev/null 2>&1 && command -v jq > /dev/null 2>&1 || return 0
  local h bands i pct epoch slot era
  h="$(curl -sf --max-time 1 http://127.0.0.1:1337/health 2> /dev/null)" || return 0
  bands="$(printf '%s' "$h" | jq -r '(.networkSynchronization // 0) as $s | if $s >= 0.999 then 4 else (($s * 4) | floor) end' 2> /dev/null)" || return 0
  case "$bands" in [0-4]) ;; *) return 0 ;; esac
  echo
  for i in 0 1 2 3; do
    if [ "$i" -lt "$bands" ]; then
      printf '  %s\n' "${SPHERE[i]}"
    else
      gray "  ${SPHERE[i]}"
    fi
  done
  # 只打印经白名单/数值化的字段（数字 tonumber?，era 仅 [A-Z0-9_-]）
  read -r pct epoch slot era < <(printf '%s' "$h" | jq -r '[(((.networkSynchronization // 0) * 100) | floor), (.currentEpoch | tonumber? // "-"), (.slotInEpoch | tonumber? // "-"), ((.currentEra // "-") | ascii_upcase | gsub("[^A-Z0-9_-]"; ""))] | @tsv' 2> /dev/null) || return 0
  if [ "$bands" -eq 4 ]; then
    printf '  SYNC ● LIVE  ·  EPOCH %s  ·  SLOT %s  ·  ERA %s\n' "$epoch" "$slot" "${era:--}"
  else
    printf '  SYNC %s%%  ·  EPOCH %s  ·  SLOT %s  ·  ERA %s\n' "$pct" "$epoch" "$slot" "${era:--}"
  fi
}

# 无 Waybar 的机器（SSH）上的单行呼吸灯：● 字形恒定，只呼吸灰阶；OFF 静止 ○
cmd_node_breathe() {
  local levels=(231 250 244 238 244 250) i state
  if ! motion_ok; then
    cmd_node_status
    return
  fi
  printf '\033[?25l'
  trap 'printf "\033[?25h\n"' EXIT
  trap 'exit 0' INT TERM
  while :; do
    state="$(node_state)"
    if [ "$state" = off ]; then
      printf '\r\033[38;5;244m○\033[0m EchoForge Node · OFF      '
      sleep 2
      continue
    fi
    for i in 0 1 2 3 4 5; do
      printf '\r\033[38;5;%sm●\033[0m EchoForge Node · %-8s' "${levels[i]}" "$state"
      sleep 0.33
    done
  done
}
