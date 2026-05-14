{ ... }:
{
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "*.md"
    "*.lock"
    "LICENSE"
  ];

  programs = {
    zig = {
      enable = true;
    };

    nixfmt = {
      enable = true;

      strict = true;
    };
  };
}
