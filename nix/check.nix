{ inputs, pkgs }:
let
  dependencies = import ./dependencies.nix { inherit inputs pkgs; };
  source = import ./source.nix { inherit (pkgs) lib; } ../.;
  expression = ''
    let lib = import ${inputs.nixpkgs}/lib;
    in import ${source}/tests {
      inherit lib;
      fx = import ${dependencies.fxSource} { inherit lib; };
    }
  '';
in
pkgs.runCommand "krisis-tests"
  {
    nativeBuildInputs = with pkgs; [ nix-unit ];
  }
  ''
    set -euo pipefail
    krisis_home_before="$HOME"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export NIX_REMOTE="local?root=$TMPDIR/store"
    export NIX_USER_CONF_FILES=/dev/null
    nix-unit --option experimental-features 'nix-command flakes pipe-operators' \
      --option substituters "" --option fallback false \
      --eval-store "local?root=$TMPDIR/store" \
      --expr ${pkgs.lib.escapeShellArg expression}
    test "$HOME" = "$krisis_home_before"
    echo "sandbox completed with HOME unchanged"
    touch "$out"
  ''
