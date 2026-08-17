{
  imports = [
    ./options.nix
    ./common/base.nix
    ./common/security.nix
    ./common/secrets.nix
    ./common/identity.nix
    ./common/doorways.nix
    ./common/console.nix
    ./cardano
    ./desktop
  ];
}
