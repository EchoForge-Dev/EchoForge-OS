# 零密钥泄露（CLAUDE.MD §4.2）
# 助记词 / 私钥 / API Key 绝不出现在源码、Nix 表达式或日志中；
# 唯一入口是 sops-nix Age 加密文件，解密挂载点固定为 /run/secrets/
{ lib, ... }:
let
  secretsFile = ../../secrets/secrets.yaml;
in
{
  sops = lib.mkIf (builtins.pathExists secretsFile) {
    defaultSopsFile = secretsFile;
    # 用主机 SSH ed25519 密钥派生 Age 身份（ssh-to-age），无需在盘上另存密钥
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # sops-nix 默认解密目录即 /run/secrets —— 与规范一致，不做任何改动
  };
}
