# 动态节点引擎（CLAUDE.MD §3）
# 绝对禁止开机自启重型节点：以下所有单元均无 wantedBy，
# 只能由 ef-cli 按需拉起 / 释放。
{
  imports = [
    ./devnet.nix
    ./mithril.nix
    ./indexers.nix
  ];
}
