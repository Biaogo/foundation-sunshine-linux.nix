{
  description = "foundation-sunshine — NixOS package for the Foundation Sunshine Linux build";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true; # cudatoolkit (CUDA builds)
            };
            inherit system;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.callPackage ./pkgs/foundation-sunshine { };
          foundation-sunshine = pkgs.callPackage ./pkgs/foundation-sunshine { };
        }
      );

      overlays.default = final: prev: {
        foundation-sunshine = final.callPackage ./pkgs/foundation-sunshine { };
      };

      checks = forAllSystems (
        { pkgs, ... }:
        {
          foundation-sunshine = pkgs.foundation-sunshine;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
