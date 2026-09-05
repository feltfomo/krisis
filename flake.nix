{
  description = "diagnostic construction, rendering, and poison-safe shape inspection for nix config libraries";

  nixConfig.extra-experimental-features = [ "pipe-operators" ];

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    axiom.url = "github:feltfomo/axiom-nix";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # consumers supply the same axiom instance as their own boundaries
      flake.lib.krisis = import ./src;

      perSystem =
        { pkgs, ... }:
        let
          axiom = inputs.axiom.lib.axiom { inherit (pkgs) lib; };
        in
        {
          treefmt = import ./formatter.nix;

          # pure cases must pass before the check derivation is admitted
          checks.tests = pkgs.runCommandLocal "krisis-tests" { } (
            assert
              (import ./tests {
                inherit (pkgs) lib;
                inherit axiom;
              }).ok;
            "touch $out"
          );

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt
              pkgs.statix
            ];
          };
        };
    };
}
