{
  description = "diagnostic construction, rendering, and poison-safe shape inspection for nix config libraries";

  nixConfig.extra-experimental-features = [ "pipe-operators" ];

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    axiom.url = "github:feltfomo/axiom-nix/d56208631f0b89b8ff0a115105ad385017aaef23";
    nix-effects = {
      url = "github:kleisli-io/nix-effects/55ec2657c3c37e178c7730992a0f510739c1f945";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      source = import ./nix/source.nix { lib = inputs.nixpkgs.lib; } ./.;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # consumers supply the same axiom instance as their own boundaries
      flake.lib.krisis = import (source + "/src");

      perSystem =
        { pkgs, ... }:
        let
          axiom = inputs.axiom.lib.axiom { inherit (pkgs) lib; };
        in
        {
          treefmt = import ./formatter.nix;

          checks.tests = import ./nix/check.nix { inherit inputs pkgs; };

          packages.qualified-nix-effects = (import ./nix/dependencies.nix { inherit inputs pkgs; }).fxSource;

          legacyPackages.qualification = import (source + "/tests") {
            inherit (pkgs) lib;
            inherit axiom;
            inherit (import ./nix/dependencies.nix { inherit inputs pkgs; }) fx;
          };

          devShells.default = pkgs.mkShell {
            inherit ((import ./nix/toolchain.nix { inherit pkgs; })) packages;
          };
        };
    };
}
