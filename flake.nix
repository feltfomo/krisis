{
  description = "diagnostic construction, rendering, and poison-safe shape inspection for nix config libraries";

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

      # krisis wants a lib and an axiom, so a consumer holding both passes them
      # straight through instead of resolving axiom a second time.
      flake.lib.krisis = import ./src;

      perSystem =
        { pkgs, ... }:
        let
          axiom = inputs.axiom.lib.axiom { inherit (pkgs) lib; };
        in
        {
          treefmt = import ./formatter.nix;

          # the suite throws on the first failing case, so evaluating .ok is the
          # whole check and the assert keeps that throw at build time.
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
              pkgs.nixfmt-rfc-style
              pkgs.statix
            ];
          };
        };
    };
}
