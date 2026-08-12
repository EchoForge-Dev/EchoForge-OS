# EchoForge 包集：ef-cli + Cardano 生态静态二进制
final: prev: {
  ef-cli = final.callPackage ./ef-cli { };

  # 上游官方发布的静态可执行文件（哈希用 scripts/prefetch-hashes.sh 填充）
  cardano-node-bin = final.callPackage ./cardano/node-bin.nix { };
  ogmios = final.callPackage ./cardano/ogmios.nix { };
  kupo = final.callPackage ./cardano/kupo.nix { };
  mithril-client-bin = final.callPackage ./cardano/mithril-client.nix { };
}
