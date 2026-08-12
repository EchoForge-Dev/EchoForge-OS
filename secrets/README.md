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

模块会自动声明对应的 `sops.secrets."pool/…"`（owner=cardano，mode=0400），
运行期解密到 `/run/secrets/pool/`，仅内存挂载、不落盘。
KES 轮换 / 重签 OpCert 后重新 `sops secrets/secrets.yaml` 编辑并
`nixos-rebuild switch`，再 `ef-cli node stop && ef-cli node start --mode mithril …` 即可。
