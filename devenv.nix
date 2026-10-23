{ pkgs, ... }:
{
  inherit ((import ./nix/toolchain.nix { inherit pkgs; })) packages;
  scripts = {
    krisis-test.exec = ''
      set -euo pipefail
      exec python3 "$DEVENV_ROOT/tools/workspace.py" test "$@"
    '';
    krisis-fmt.exec = ''
      set -euo pipefail
      exec python3 "$DEVENV_ROOT/tools/workspace.py" format
    '';
    krisis-gate.exec = ''
      set -euo pipefail
      exec devenv test "$@"
    '';
  };
  tasks = {
    "check:format" = {
      exec = "python3 tools/workspace.py check-format";
      showOutput = true;
    };
    "check:nix" = {
      after = [ "check:format" ];
      exec = "python3 tools/workspace.py static";
      showOutput = true;
    };
    "gate:flake" = {
      after = [ "check:nix" ];
      exec = "python3 tools/workspace.py flake";
      showOutput = true;
    };
    "gate:all".after = [ "gate:flake" ];
    "devenv:enterTest".after = [ "gate:all" ];
  };
}
