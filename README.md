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

## Releases

Prebuilt tarballs are attached to the fork's releases. The
[`v2026.09.07-linux`](https://github.com/Biaogo/foundation-sunshine-linux/releases/tag/v2026.09.07-linux)
tag is force-updated to track the `linux-support` fix series (currently
`33051b67`: virtual-display routing under dual capture sources, ambient
CAP_SYS_ADMIN shedding, KWin permission-gate workaround docs) — this pin
follows that tag commit exactly, so the flake hash and the release tarball
are built from the same source tree.

Nix users should prefer the flake — it wires up the full runtime
closure (ffmpeg/boost statics, CUDA, pipewire, avahi) that a bare tarball
cannot provide on non-NixOS distros.

## License

GPL-3.0-only (same as upstream Sunshine).
