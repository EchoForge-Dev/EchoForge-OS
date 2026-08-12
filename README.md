<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/echoforge-lockup-white.png">
  <img src="docs/brand/echoforge-lockup-black.png" alt="EchoForge OS" width="440">
</picture>

<br>

**A declarative NixOS distribution for the full Cardano stack — one base, four profiles.**

![NixOS](https://img.shields.io/badge/NixOS-unstable%20%C2%B7%20flakes-black?style=flat-square&logo=nixos&logoColor=white&labelColor=black)
![Cardano](https://img.shields.io/badge/Cardano-node%2010.1.4-black?style=flat-square&logo=cardano&logoColor=white&labelColor=black)
![Platforms](https://img.shields.io/badge/platforms-x86__64%20%C2%B7%20aarch64-black?style=flat-square&labelColor=black)
![License](https://img.shields.io/badge/license-Apache--2.0-black?style=flat-square&labelColor=black)
![flake check](https://img.shields.io/badge/nix%20flake%20check-passing-4ade80?style=flat-square&labelColor=black)

</div>

---

EchoForge OS (EFOS) is a NixOS-based operating system for everyone who touches Cardano —
stakers, dApp developers, stake-pool operators and DePIN fleet runners. Instead of four
separate distros, it ships **one shared, hardened base** and four build targets that differ
only in which modules get wired in. Everything is a flake output: rebuild it anywhere,
bit-for-bit, from this repository.

<img src="docs/figures/01-architecture.png" alt="Architecture — one shared base, the echoforge.* option namespace, and four profile cards showing which modules each wires in">

## The four profiles

| Profile | Audience | Form | In one line |
|---|---|---|---|
| `echoforge-desktop` | Hobbyist · staking & browsing | GUI light desktop | Read-only desktop with Lace + Ledger; the node is entirely absent — zero overhead |
| `echoforge-dev` | Smart-contract developer | GUI/CLI sandbox | On-demand local devnet (~200 MB, second-level blocks) + Aiken / GHC / Ogmios / Kupo + Zed |
| `echoforge-spo` | Power user · protocol & full node | GUI/TUI hybrid | Mithril snapshot sync for preview / preprod / mainnet, TUI monitoring, optional block producer |
| `echoforge-depin` | DePIN edge node | Headless · RPi4 | aarch64, tmpfs root, ZRAM, hardware watchdog — survives power loss unattended |

## Quick start

```bash
git clone https://github.com/EchoForge-Dev/EchoForge-OS.git
cd EchoForge-OS

# 1. Build any profile closure (on NixOS or a Linux builder)
nix build .#nixosConfigurations.echoforge-dev.config.system.build.toplevel

# 2. Activate it on the target machine
sudo nixos-rebuild switch --flake .#echoforge-dev

# 3. depin: flashable RPi4 SD image (.img.zst — root partition auto-expands on first boot)
nix build .#packages.aarch64-linux.depin-sd-image
```

> **Disk conventions** — partition by label at install time, no code changes needed:
> `echoforge-root` (ext4) + `EFOS-BOOT` (vfat) for the desktop-class profiles;
> the depin SSD deployment (`echoforge-depin`) expects `echoforge-nix`, `echoforge-data`,
> optional `echoforge-swap` and `FIRMWARE`; the SD-image form (`echoforge-depin-sd`)
> needs no manual partitioning at all.

To bump an upstream binary, edit the `version` in `pkgs/cardano/*.nix` and run
`./scripts/prefetch-hashes.sh` to re-verify and fill in the SRI hashes.

## `ef-cli` — the dynamic node engine

The system **never** boots a heavyweight node. No node unit declares `wantedBy`, so nothing
enters the boot dependency tree — `ef-cli` is the only way up, and `stop` is a full release:

```bash
ef-cli node start --mode devnet                      # local private chain (~200 MB, second-level blocks)
ef-cli node start --mode mithril --network preview   # Mithril snapshot → preview/preprod/mainnet
ef-cli node stop                                     # release all node memory & CPU
ef-cli node status [--waybar]                        # status query / status-bar JSON
ef-cli profile switch <desktop|dev|spo|depin>        # nixos-rebuild into another profile
```

The monochrome breathing light on the Waybar tracks it live: gray = OFF, bright white = running.
One socket for everything: `/run/echoforge/node.socket`; Ogmios at `127.0.0.1:1337`, Kupo at `127.0.0.1:1442`.

<img src="docs/figures/02-footprint.png" alt="Resource footprint — 0 MB / 0% CPU node usage after boot on all four profiles, declared memory ceilings, and per-profile quota comparison">

## Security model

- **Immutable system** — `users.mutableUsers = false`; every change goes through
  `flake.nix` + `nixos-rebuild`. No runtime `apt`/`pacman`, no hand-editing `/etc`.
- **Zero secret leakage** — sensitive material exists only as sops-nix Age ciphertext,
  decrypted to the in-memory mount `/run/secrets/` (see [secrets/README.md](secrets/README.md)).
- **Network isolation** — node / Ogmios / Kupo bind to `127.0.0.1` and a **build-time
  assertion** guards it; the firewall denies all inbound by default, with SSH (key-only)
  opened solely on `spo` / `depin`.

<img src="docs/figures/03-security.png" alt="Security posture matrix — five hard rules enforced on every profile, open-port counts per profile, and the per-safeguard comparison table">

## Preinstalled on the desktop profiles (desktop / dev / spo)

| App | Integration |
|---|---|
| **Lace Wallet** | Forced install via Chrome enterprise policy `ExtensionInstallForcelist` — works out of the box |
| **Ledger** | `hardware.ledger.enable = true` + udev rules — plug and use |
| **Zed Editor** | Preinstalled with the EFDS dark high-contrast theme + Aiken / Haskell / Nix extensions |
| **Google Chrome** | Homepage & new-tab policy locked to echoforgellc.tech / stickmancharles.com |

<img src="docs/figures/04-features.png" alt="Capability matrix — desktop and wallet apps, node subsystems and ops tooling across the four profiles">

## SPO block production

Uncomment `mithril.blockProducer.enable = true;` in `profiles/spo.nix`, put the KES / VRF /
OpCert material into sops (`secrets/secrets.yaml`, decrypted to `/run/secrets/pool/`), and the
`ef-node@` unit automatically appends `--shelley-kes-key` / `--shelley-vrf-key` /
`--shelley-operational-certificate`. If the secrets are missing, a build-time assertion
refuses to build — you cannot ship a producer without its keys.

<img src="docs/figures/05-spo.png" alt="SPO workflow — ef-cli triggers the Mithril snapshot sync unit, then the full-node unit; block-production keys are injected via sops; relay vs producer comparison">

## Repository layout

```
flake.nix                  # four profile build targets + package outputs
├── profiles/              # desktop / dev / spo / depin (+ depin disk layouts)
├── modules/
│   ├── options.nix        # the echoforge.* option namespace
│   ├── common/            # immutable base · security policy · sops-nix secrets
│   ├── cardano/           # dynamic node engine (devnet / mithril / ogmios+kupo units)
│   └── desktop/           # Hyprland + Waybar GUI, Lace / Ledger / Zed / Chrome integration
├── home/                  # EFDS visual layer (Waybar breathing light, Zed theme)
├── pkgs/                  # ef-cli + static Cardano binary packaging
├── scripts/               # node runners + hash-prefetch tooling
├── secrets/               # sops-nix Age templates (decrypt to /run/secrets)
└── docs/                  # engineering figures + brand assets
```

## Known limitations

1. **aarch64 node trust chain** — the `cardano-node-bin` aarch64 static binaries come from the
   community [Armada Alliance](https://github.com/armada-alliance/cardano-node-binaries) builds
   (musl static, version-aligned with the official x86_64 10.1.4 binaries). If you require
   same-origin builds, compile from source via haskell.nix and override `cardano-node-bin`
   in the overlay.
2. **Real-hardware validation** — the `echoforge-depin-sd` image (sd-image-aarch64 +
   nixos-hardware RPi4) has not yet been flashed and verified on a physical RPi4.
3. **Producer topology** — the block producer currently follows the public topology. A
   production SPO should run a private "producer peers only with its own relays" topology
   (extending `node-run.sh` with a custom `topology.json` is all it takes).

## License

Code is licensed under [Apache-2.0](LICENSE.md). The EchoForge name, wordmarks and logo
assets under `docs/brand/` are **not** open source — see [LICENSE-NOTICE.md](LICENSE-NOTICE.md).

<div align="center">
<sub>Design language: EchoForge Design System — pure black / white / gray, four status colors, IBM Plex Mono.</sub>
</div>
