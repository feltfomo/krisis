{
  inputs,
  pkgs,
  source ? import ./qualified-source.nix,
}:
let
  corrected = pkgs.applyPatches {
    name = "nix-effects-validation-reference";
    src = inputs.nix-effects;
    patches = [ ../patches/nix-effects-validation.patch ];
    patchFlags = [
      "-p1"
      "--fuzz=0"
    ];
  };
in
pkgs.runCommand "qualified-nix-effects" { } ''
  set -euo pipefail
  diff --recursive --no-dereference ${corrected} ${source}
  find ${corrected} -type f -perm /111 -printf '%P\n' | sort > reference-executables
  find ${source} -type f -perm /111 -printf '%P\n' | sort > source-executables
  diff reference-executables source-executables
  cp -a ${source} "$out"
''
