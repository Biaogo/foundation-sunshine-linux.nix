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

## Notes

- CUDA/NVENC is enabled automatically when `cudaPackages` is available;
  pass `override { cudaPackages = null; }` to build without it.
- The KWin capture backend (`capture = kwin`) is included, so
  [krfb-virtualmonitor](https://docs.kde.org/stable/en/kdenetwork/krfb/krfb-virtualmonitor.html)
  virtual outputs can be streamed — useful for phone-as-second-screen setups.
- Windows-only components (ZakoVDD virtual display driver, vmouse, vsink,
  RTX HDR) are stubbed out upstream-style and are inert on Linux.

## License

GPL-3.0-only (same as upstream Sunshine).
