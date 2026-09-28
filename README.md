# foundation-sunshine-linux.nix

NixOS package for [Foundation Sunshine](https://github.com/Biaogo/foundation-sunshine-linux) —
the qiin2333 fork of [LizardByte/Sunshine](https://github.com/LizardByte/Sunshine), built for
Linux from the [`linux-support`](https://github.com/Biaogo/foundation-sunshine-linux/tree/linux-support)
branch.

## Usage

### flake (recommended)

```nix
# flake.nix
{
  inputs.foundation-sunshine-linux-nix.url = "github:Biaogo/foundation-sunshine-linux.nix";

  outputs = { self, nixpkgs, foundation-sunshine-linux-nix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            foundation-sunshine-linux-nix.packages.x86_64-linux.default
          ];
        })
      ];
    };
  };
}
```

Or via the overlay:

```nix
nixpkgs.overlays = [ foundation-sunshine-linux-nix.overlays.default ];
```

### Direct build

```bash
nix build github:Biaogo/foundation-sunshine-linux.nix
./result/bin/sunshine
```

## Deployment notes (Linux)

- **KMS capture (kmsgrab) needs `CAP_SYS_ADMIN`.** On NixOS use a setcap
  wrapper (`security.wrappers.sunshine` with `cap_sys_admin+p`) and point the
  service's `ExecStart` at `/run/wrappers/bin/sunshine`. The binary itself is
  capability-free.
- **KWin ScreenCast and file capabilities don't mix.** KWin ≥ 6.6 gates the
  `zkde_screencast_unstable_v1` protocol per client by readlinking
  `/proc/<pid>/exe`; a setcap-wrapped process is non-dumpable, so the exe is
  unreadable and KWin refuses the protocol (`not found in registry`). The
  practical fix is upstream's documented workaround: set
  `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` both in the **desktop session**
  environment (this is what KWin itself reads — e.g.
  `environment.sessionVariables` on NixOS) and in the sunshine service
  environment (this skips Sunshine's own permission-desktop-file handling).
  Pre-login (SDDM) KMS streaming is unaffected either way.
- **Virtual displays** (phone-as-second-screen): the branch's KWin capture
  backend can stream [krfb-virtualmonitor](https://docs.kde.org/stable/en/kdenetwork/krfb/krfb-virtualmonitor.html)
  outputs. Note the output is created DISABLED — enable it with
  `kscreen-doctor output.<uuid>.enable` (a `global_prep_cmd` do/undo hook can
  wire this to session start/stop), and that `--resolution` takes a single
  `WIDTHxHEIGHT` token (no spaces).
- **`/dev/uinput` under a linger user service**: uaccess ACLs only apply while
  the user owns an active session, but a linger sunshine starts before login —
  virtual mouse/keyboard then fail with Permission denied for the service's
  lifetime. Add a static udev rule
  (`KERNEL=="uinput", GROUP="input", MODE="0660"`) and put the user in the
  `input` group.
- Windows-only components (ZakoVDD virtual display driver, vmouse, vsink,
  RTX HDR) are stubbed out upstream-style and are inert on Linux.

### Headless hosts & the login manager (SDDM/GDM)

A dynamic virtual monitor cannot exist at the greeter: it lives inside the
streaming user's compositor, which does not exist before login (the greeter's
own compositor belongs to the `sddm`/`gdm` user and is unreachable across
Wayland's socket isolation — and running Sunshine as the greeter user is a
security anti-pattern). Pre-login the KMS backend can only stream a
*connector*, whose modes are fixed by EDID at boot.

The standard architecture: a small **static login head** (forced connector +
custom EDID, or a `vkms` virtual DRM device) for the greeter, then the
**dynamic krfb-virtualmonitor** takes over after login with the client's
resolution/fps. Full walkthrough including autologin+lock, the KWin
permission-gate workaround, and troubleshooting:
[linux-headless-sddm-streaming.md](https://github.com/Biaogo/foundation-sunshine-linux/blob/linux-support/docs/linux-headless-sddm-streaming.md).
A complete NixOS deployment page (flake usage, module snippets, the virtual
display hooks in full — **KDE Plasma only**) lives at
[nixos-sunshine.md](https://github.com/Biaogo/foundation-sunshine-linux/blob/linux-support/docs/nixos-sunshine.md).

## Releases

Prebuilt tarballs are attached to the fork's releases. The
[`v2026.09.28.3-linux`](https://github.com/Biaogo/foundation-sunshine-linux/releases/tag/v2026.09.28.3-linux)
tag tracks the re-forked Linux lineage (`refork/linux`: upstream/master plus the
re-applied host patches; currently `ee837406`, which adds the in-session re-verification
of the KWin capture source so a linger service started before the compositor no longer
answers 503 on every display pick) — this pin
follows that tag commit exactly, so the flake hash and the release tarball
are built from the same source tree.

Nix users should prefer the flake — it wires up the full runtime
closure (ffmpeg/boost statics, CUDA, pipewire, avahi) that a bare tarball
cannot provide on non-NixOS distros.

## Binary cache

CI (`.github/workflows/update-pin-and-cache.yml`) builds
`.#foundation-sunshine-upstream` and pushes **three** paths to Cachix after
every pin update: the package closure, the web UI (`…-ui-<ver>`, a
build-time-only input) and the git source FOD (`fetchSubmodules = true` clones
~20 repos, so publishing it saves downstream builds the fragile part). The
build is the CUDA/NVENC variant — `cudaPackages ? null` gets filled in by
`callPackage`, giving `-DSUNSHINE_ENABLE_CUDA:BOOL=TRUE` in this flake's own
evaluation.

The cache is the **free 5 GB tier** and one pin's three paths already take
~3.2 GiB (UI 1.66 + source 1.48 + closure ≈ 0.03). A push on its own is
therefore *not* durable: with the cache near its cap the collector evicted a
freshly pushed closure minutes after the job's own self-check had passed. So
the workflow **pins** every path after confirming it reads back —
`fsl-closure` with `--keep-revisions 3`, `fsl-ui` and `fsl-src` with
`--keep-revisions 1` — because pinned paths are immune to garbage collection
while the retention flags still let the previous generation be freed. A
`cachix pin … failed` warning in the log means that path stayed GC-able: check
the token scope and plan limits at app.cachix.org.

**Pruning is dashboard-only** — the CLI ships no delete/gc command (`cachix`
has push / pin / import / watch-store; `remove` only edits your local
nix.conf). To shrink the cache:

- `https://app.cachix.org/cache/biaogo/pins` — inspect and delete pins;
  deleting one makes its store paths collectable again
- the cache's *Garbage Collection* page — shows exactly which paths would be
  deleted first when the limit is reached
- search a store path and delete it directly

Two documented traps that make "just push it again" a bad strategy: pushing a
path does **not** override an existing entry (it must be deleted first), and GC
running *while* a push is in flight surfaces `InvalidPath` errors — which is why
the important paths are pinned instead of re-pushed.

Skip the compile entirely:

```bash
cachix use biaogo        # or add the substituter + key to your nix.settings
nix build github:Biaogo/foundation-sunshine-linux.nix
```

**Cache-key caveat:** a Nix cache is keyed by derivation, not by package name.
Substitution only hits when you build this expression with **this repo's own
nixpkgs pin** — i.e. through the flake (`nix build github:…`, or
`inputs.<fsl>.packages.<system>.foundation-sunshine-upstream`). A consumer that
re-`callPackage`s the expression against its *own* nixpkgs revision produces a
different derivation (different deps) and will always miss, ending up with a
local build. If you control the consumer, consume the flake output — that is
exactly what the NixOS host does (see the next section).

### How the host consumes this repo (and why the cache always hits)

The NixOS host takes the package **verbatim from this repo's own output**:

```nix
# host flake.nix — deliberately NO `inputs.nixpkgs.follows` on this input
foundation-sunshine-linux.url = "github:Biaogo/foundation-sunshine-linux.nix";
# host pkgs/default.nix
foundation-sunshine =
  inputs.foundation-sunshine-linux.packages.${pkgs.system}.foundation-sunshine-upstream;
```

Because the host does not force this flake onto its own nixpkgs, the derivation
it asks for is *by construction* the one this repo builds and publishes to
`biaogo.cachix.org` — so the cache always hits and the host never compiles
Sunshine. Measured 2026-09: host drv `q0yhzi9n1ax6s2z8zisfl1m9fi002dha-…` == CI
drv, and its output `0vfcm1sagj…` is HIT in the cache.

That makes **this repo the single source of truth for the nixpkgs rev** — the
opposite of a `follows` setup, where the host's rev decides and the CI can never
match it. Tracking the tip of `nixos-unstable` is therefore intentional:

- `update-pin-and-cache.yml` does both halves in one run: it first moves
  `flake.lock` to the branch tip (on every 30-min poll; a manual run can switch
  that off with the `bump_nixpkgs` checkbox), then — if anything actually moved —
  builds and pushes, so the cache is refreshed for the new rev automatically.
  One `Plan` step decides; no secrets, nothing outside this repo.
- the host's `nh os switch -u` picks up this repo's newest commit and therefore
  asks for exactly the artifact that was just published.

Two rules follow — either violation re-introduces the miss:

1. do not pin this repo's nixpkgs to a fixed rev, and
2. do not put `inputs.nixpkgs.follows = "nixpkgs"` back on the host side (nor
   switch the host back to `callPackage`-ing the expression).

| | |
|---|---|
| Substituter | `https://biaogo.cachix.org` |
| Public key | `biaogo.cachix.org-1:pEsKASFTETzWAVGGsjpHnq869V5KNeDOBhQahLlrPzY=` |

Cache repair / manual push (maintainer) — the workflow does this itself,
verifies each path reads back, and then pins all three.

When verifying by hand, beware nix's **negative narinfo cache**: a
`nix path-info --store https://biaogo.cachix.org <path>` issued before a push has
propagated keeps reporting MISS for up to an hour even though the path is fine.
Use `--option narinfo-cache-negative-ttl 0` (or fetch `<hash>.narinfo` with curl)
**and** keep a control path that must still miss — otherwise you can "reproduce"
a cache loss that never happened (2026-09: that mistake cost a multi-round
investigation into a garbage-collection problem that did not exist).

```bash
OUT=$(nix build .#foundation-sunshine-upstream --no-link --print-out-paths)
UI=$(nix build .#foundation-sunshine-upstream.ui --no-link --print-out-paths)
SRC=$(nix eval --raw .#foundation-sunshine-upstream.src.outPath)
nix-store --realise "$SRC"

cachix push biaogo "$OUT" "$UI" "$SRC"

# A push that is not readable back is a push that did not happen.
for p in "$OUT" "$UI" "$SRC"; do
  nix path-info --store https://biaogo.cachix.org "$p" >/dev/null || echo "MISS: $p"
done

# Pins are what make it survive the collector (see above).
cachix pin biaogo fsl-closure "$OUT" --keep-revisions 3
cachix pin biaogo fsl-ui      "$UI"  --keep-revisions 1
cachix pin biaogo fsl-src     "$SRC" --keep-revisions 1
```


## License

GPL-3.0-only (same as upstream Sunshine).
