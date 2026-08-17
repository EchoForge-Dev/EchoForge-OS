# EchoForge 密钥管理（零密钥泄露）

**绝对禁止**在源码、Nix 表达式或日志中出现助记词、私钥 Hex 或 API Key。

唯一合法路径：

```bash
# 1. 生成主机 Age 公钥（由 SSH ed25519 主机密钥派生）
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub

# 2. 填入 .sops.yaml 后创建/编辑加密文件
nix develop -c sops secrets/secrets.yaml

# 3. 在 Nix 模块中声明（示例）
#    sops.secrets."pool/kes.skey" = { owner = "cardano"; };
#    运行期出现在 /run/secrets/pool/kes.skey —— 仅内存，不落盘
```

`secrets.yaml`（加密后）可以提交进仓库；任何 `*.skey`、明文密钥文件已被
`.gitignore` 拦截，但拦截不是许可 —— 明文密钥根本不应该出现在这个目录里。

## SPO 出块密钥（blockProducer）

启用 `echoforge.node.mithril.blockProducer.enable = true;` 后，
`ef-node@` 单元自动追加 `--shelley-kes-key` / `--shelley-vrf-key` /
`--shelley-operational-certificate`。三份材料必须放进 `secrets.yaml`：

```yaml
# nix develop -c sops secrets/secrets.yaml
pool:
  kes.skey: |
    { "type": "KesSigningKey_ed25519_kes_2^6", ... }
  vrf.skey: |
    { "type": "VrfSigningKey_PraosVRF", ... }
  node.cert: |
    { "type": "NodeOperationalCertificate", ... }
```

模块会自动声明对应的 `sops.secrets."pool/…"`，运行期解密到 `/run/secrets/pool/`，
仅内存挂载、不落盘。权限按材料性质分开：

| 文件 | 模式 | 理由 |
|---|---|---|
| `pool/kes.skey` | `0400` | 签名私钥，只有 cardano 用户读 |
| `pool/vrf.skey` | `0400` | 同上 |
| `pool/node.cert` | `0440` | 操作证书随区块头公开上链，本就不是秘密；放开组内可读，运维用户才跑得动 `ef-cli pool status` |

## KES 轮换

KES 密钥有效期有限（mainnet 一个周期 129600 slots，最多 62 个周期），到期不换就停止出块。
在出块机上跑：

```bash
ef-cli pool status        # 看当前周期、证书有效区间、链上 vs 本地计数器
ef-cli pool rotate-kes    # 生成新 KES 密钥对 + 打印离线重签步骤
```

`rotate-kes` 把新密钥对写进 `$XDG_RUNTIME_DIR/ef-pool-rotate`（tmpfs 内存挂载，
重启即消失），并按链上 tip 与 shelley 创世算出当前 KES period。**它到此为止**：
冷密钥在离线签名机上，`issue-op-cert` 必须在那边完成 —— 命令连同算好的
`--kes-period` 会直接打印出来。

拿回新的 `node.cert` 后：

```bash
nix develop -c sops secrets/secrets.yaml     # 更新 pool/kes.skey 与 pool/node.cert
sudo nixos-rebuild switch --flake .#echoforge-spo
ef-cli node stop && ef-cli node start --mode mithril --network mainnet
ef-cli pool status                           # 确认链上计数器追上本地计数器
rm -rf "$XDG_RUNTIME_DIR/ef-pool-rotate"     # 清掉内存里的明文 KES 私钥
```
