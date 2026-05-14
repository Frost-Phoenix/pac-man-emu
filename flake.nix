{
  description = "Pac-Man arcade emulator";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    zig-overlay = {
      url = "github:silversquirl/zig-flake/compat";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      zig-overlay,
      treefmt-nix,
      ...
    }:
    let
      supportedSystems = [ "x86_64-linux" ];

      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            zig = zig-overlay.packages."${system}".zig_0_16_0;
            zls = zig-overlay.packages."${system}".zig_0_16_0.zls;
          }
        );

      treefmtEval = forEachSupportedSystem (
        { pkgs, ... }: treefmt-nix.lib.evalModule pkgs ./nix/treefmt.nix
      );
    in
    {
      devShells = forEachSupportedSystem (
        {
          pkgs,
          zig,
          zls,
        }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              zig
              zls

              zigimports
            ];

            env = {
              ZIG_BUILD_ERROR_STYLE = "minimal";
            };
          };
        }
      );

      formatter = forEachSupportedSystem (
        { pkgs, ... }: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
      );
    };
}
