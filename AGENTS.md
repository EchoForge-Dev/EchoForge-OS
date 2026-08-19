# AGENTS.md

Instructions for an AI agent operating an EchoForge OS machine, or editing this repository on
behalf of its operator. Read this before running anything.

EchoForge OS is **declarative and immutable**. The running system is a build artifact of
`flake.nix`; it is not a place where state accumulates. Almost every instinct carried over from
Ubuntu or Arch — install a package, edit a file under `/etc`, enable a service — is not merely
discouraged here, it silently does nothing that survives the next rebuild. Work with the model
rather than around it.

Two contexts, and they call for different actions:

| Where you are | What you can change |
|---|---|
| SSH'd into a running machine | Node lifecycle via `ef-cli`; read logs and state. Nothing persistent. |
| In a checkout of this repository | Everything — by editing Nix expressions and rebuilding. |

---

## Never do these

**Never install software at runtime.** No `apt`, `pacman`, `nix-env -i`, `curl | sh`. There is
no package manager to reach for, and anything you place under `/usr` or `/etc` by hand is gone
at the next `nixos-rebuild`. To add a package, edit `environment.systemPackages` in the relevant
profile or module and rebuild.

**Never write a secret anywhere except sops.** No seed phrase, private key hex, or API key may
appear in source, in a Nix expression, in a shell history, or in a log line — including in a
command you run to "check" one. The only legal path is `secrets/secrets.yaml`, Age-encrypted,
decrypted at runtime to `/run/secrets/` (memory-backed, never on disk). See
[secrets/README.md](secrets/README.md). If you find yourself about to echo a key to verify it,
stop.

**Never `systemctl enable` a node unit.** `ef-devnet`, `ef-node@`, `ef-ogmios`, `ef-kupo` and
`ef-mithril-sync@` deliberately declare no `wantedBy`, so they never enter the boot dependency
tree. That is the design: a freshly booted machine runs 0 MB / 0% CPU of node. Enabling one
breaks the guarantee the whole system is built around.

**Never point `echoforge.node.hostAddr` at a public address to make a relay reachable.** That
option governs the RPC surface (Ogmios, Kupo, the devnet node) and is guarded by a build-time
assertion. The full node's P2P bind address is `echoforge.node.mithril.p2pAddr`, and it already
defaults to `0.0.0.0`. Inbound reachability is `mithril.openFirewall`, not a bind address.

**Never delete `/var/lib/echoforge/<network>/db` or its `.ef-mithril-complete` marker** to "fix"
a sync. That discards a certified snapshot and costs hours to restore. Diagnose first.

**Never assume a rebuild restarted the node.** Node units set `restartIfChanged = false` — a
restart before the node has written its first ledger snapshot forces a full replay from genesis
(46 minutes on preview, hours on mainnet). After changing node code or the node version, restart
explicitly, at a moment the operator has agreed to.

---

## `ef-cli` is the only entry point

```bash
ef-cli node start --mode devnet                      # local private chain, ~2 s blocks
ef-cli node start --mode mithril --network preview    # snapshot-bootstrapped full node
ef-cli node stop                                      # releases all node memory and CPU
ef-cli node status                                    # ● running / ◐ restoring / ○ off
ef-cli pool status [--network N] [--json]             # KES period, cert validity, counters
ef-cli pool rotate-kes [--network N]                  # new KES pair + offline re-signing steps
ef-cli profile switch <desktop|dev|spo|depin>         # rebuild into another profile
ef-cli version                                        # version, active profile, build revision
```

One socket for everything: `/run/echoforge/node.socket`, with `CARDANO_NODE_SOCKET_PATH` already
pointing at it, so plain `cardano-cli query tip` works. Ogmios is on `127.0.0.1:1337`, Kupo on
`127.0.0.1:1442`.

**Passwordless sudo is scoped to exactly three commands**: `systemctl start|stop|restart ef-*`.
Everything else — `nixos-rebuild` included — prompts for a password. In a non-interactive
session that prompt will hang. Ask the operator to run rebuilds, or to grant you a way to
authenticate; do not try to widen the sudoers rule.

Machine facts live in `/etc/echoforge/`: `profile` (the active profile) and `flake.ref` (the
flake `ef-cli` rebuilds from). Read them instead of guessing.

---

## Changing the system

```bash
# 1. edit the Nix expression — profiles/<profile>.nix, modules/**, or flake.nix
# 2. rebuild (asks for a password)
sudo nixos-rebuild switch --flake .#echoforge-<profile>
# 3. if it misbehaves, roll back — every build is a generation
sudo nixos-rebuild switch --rollback
```

`nixos-rebuild build` or `nix flake check` first is cheap and catches most mistakes without
touching the running system. Options are namespaced under `echoforge.*` and declared in one
place, [modules/options.nix](modules/options.nix) — read the option's `description` before
setting it; several of them carry the reasoning for a non-obvious default.

Where things live:

```
profiles/     one file per profile; depin's hardware specifics are separate overlays
modules/
  common/     immutable base, security policy, sops, machine identity
  cardano/    the node engine — devnet, mithril, indexers, LED
  desktop/    GUI, wallets, browser policy
pkgs/         ef-cli and the pinned Cardano binaries
scripts/      what the node units actually execute
secrets/      sops templates; the encrypted file itself is safe to commit
```

---

## Diagnose before acting

Every entry below is a real failure that has been observed on hardware. The pattern they share:
the surface reading is reassuring and the underlying state is not.

**"Sync is at 99% but the tip never advances."** Check the peer count before anything else. A
node bound to loopback for P2P cannot make outbound connections — `--host-addr` also fixes the
source address, so every `connect()` returns `EINVAL` — and it will sit at the snapshot's last
block forever while `syncProgress` reports 99%+. Confirm `p2pAddr` is `0.0.0.0`, then look for
`EINVAL` in `journalctl -u ef-node@<network>`.

**"`ef-cli node start` said it is still starting."** That is an honest report, not a failure. A
Mithril snapshot carries no ledger state, so the node replays from genesis before opening the
socket. Watch `journalctl -fu ef-node@<network> | grep LedgerReplay`. Do not kill it; do not
start the indexers until the socket exists.

**"Ogmios or Kupo dies immediately with `Yaml file not found`."** They resolve relative genesis
paths against the directory of the symlink they were handed, so all four genesis files must be
linked next to `node-config.json` in `/run/echoforge/`. If they are missing, the node was not
started through its unit.

**"The devnet is in a crash-restart loop."** Look at whether the genesis matches the current
`cardano-cli`: the parameter set moves with the binary, and a mismatch is fatal. `ef-cli node
start --mode devnet` regenerates and says so. The devnet chain is disposable by design — never
store anything on it you would miss.

**"`ef-cli pool status` says the producer is off, but it is configured."** It reads the
operational certificate path from the node unit, so this means the certificate is genuinely
unreadable: check that sops decrypted it (`ls -l /run/secrets/pool/`), that the owner is
`cardano` and `node.cert` is `0440`, and that your account is in the `cardano` group — group
changes need a fresh login.

**"The Mithril database is downloading again."** It only re-downloads when
`.ef-mithril-complete` is absent, which means the previous restore did not finish. If you are
confident an existing database is complete, mark it rather than letting it re-download.

When a command fails, read its actual output before theorizing. Most of the tooling here prints
the reason; the failures worth escalating are the ones that do not.

---

## Stop and ask a human

Do not act unilaterally on any of these, even if you are confident and even if you were asked
to "handle it":

- **Anything touching keys or funds** — generating, moving, or using a payment, stake, or cold
  key; signing or submitting a transaction; anything that spends ADA. `ef-cli pool rotate-kes`
  deliberately stops after generating the KES pair: re-issuing the operational certificate needs
  the cold key, which lives on an offline signer and must stay there.
- **Destructive state operations** — deleting a chain database, repartitioning, reinstalling,
  or wiping `/var/lib/echoforge`.
- **Opening a port to the internet**, or any change that widens the attack surface.
- **Restarting a producing block-producer node.** That is downtime; the operator picks when.
- **A rebuild on a machine you cannot recover** — a headless box with no SSH key declared has
  only console rescue left.

Report what you found and what you would do. Being useful here means being precise about the
state of the machine, not being the one who pressed the button.

---

## Reporting back

Say what you actually observed, quoting the command and its output. If you did not verify
something, say so — "the unit is active" and "the node has peers" are different claims, and on
this system the gap between them has been an entire class of bug. If a step failed, report the
failure rather than the plan that was supposed to work.
