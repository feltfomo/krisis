{ pkgs }:
{
  packages = with pkgs; [
    nixVersions.nix_2_35
    nix-unit
    nixfmt
    statix
    python3
  ];
}
