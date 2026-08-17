# EchoForge 品牌常量 —— 纯 attrset（import ./brand.nix），无 option、无 config。
# 系统层彩蛋（identity / doorways / 单元 Documentation=）与 ef-cli 共享的字符串在此只写一次。
{
  motto = "All for Simple";
  mottoZh = "一切为简";
  genesis = "2026-04-11"; # EchoForge 成立日
  genesisEpoch = 1775865600; # 2026-04-11T00:00:00Z
  epochLength = 432000; # 5 天，同 mainnet —— ef-cli genesis 用它把成立日当 epoch 0
  home = [
    "https://echoforgellc.tech"
    "https://stickmancharles.com"
  ];
  family = [
    "EchoCert"
    "EchoUploader"
    "EchoID"
    "EchoDash"
    "EchoVote"
    "ForgeCard"
  ];
  # 每个 ef-* 单元的 [Unit] Documentation=（systemctl status 多一行 Docs:）
  unitDocumentation = [
    "https://echoforgellc.tech"
    "https://github.com/EchoForge-Dev/EchoForge-OS"
    "file:/etc/echoforge/genesis.json"
  ];
  # mark-medium：命令行化的 EchoForge 球标（30×13）。只用 ▀ ▄ █（IBM437 控制台字体自带 → 裸 VT 可渲染），
  # 不含反斜杠（agetty 的 /etc/issue 转义安全）。
  markMedium = ''
            ▄▄▄▄▄▄▄
          ▀▀▀▀▀▀██████▄▄▄▄▄▄▄
       ▄▄▄▄▄▄▄▄▄   ▀▀▀████████▄
     ▄█████████████▄▄▄         ▄▄
     ▀▀         ▀▀▀██████████████
    ▄▄▄█████████▄▄▄   ▀▀▀▀▀▀▀▀▀
    ███▀▀▀▀▀▀▀▀▀██████▄▄▄▄▄▄▄▄▄███
       ▄▄▄▄▄▄▄▄▄   ▀▀▀█████████▀▀▀
     ██████████████▄▄▄         ▄▄
     ▀▀         ▀▀▀█████████████▀
       ▀████████▄▄▄   ▀▀▀▀▀▀▀▀▀
         ▀▀▀▀▀▀▀██████▄▄▄▄▄▄
                   ▀▀▀▀▀▀▀'';
}
