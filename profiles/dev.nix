# Profile 2 — echoforge-dev（普通开发者 / Smart Contract Sandbox）
# GUI/CLI 混合；按需 Local Devnet（~200MB，秒级出块）+ Aiken/GHC/Ogmios/Kupo/Zed
{ pkgs, ... }:
{
  networking.hostName = "echoforge-dev";

  echoforge = {
    profile = "dev";
    gui.enable = true;
    node = {
      devnet.enable = true; # 单元就位，但只能 ef-cli node start --mode devnet 拉起
      mithril.enable = true; # 允许开发者按需挂测试网
      indexers.enable = true; # Ogmios :1337 + Kupo :1442（仅 127.0.0.1）
    };
  };

  # 智能合约开发工具链
  environment.systemPackages = with pkgs; [
    aiken
    ghc
    cabal-install
    haskell-language-server
    nodejs_22
    just
  ];

  services.openssh.enable = false;
}
