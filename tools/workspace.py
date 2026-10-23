#!/usr/bin/env python3
"""include untracked candidates because Git flakes omit them before staging"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def candidates():
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    )
    return sorted({os.fsdecode(name) for name in output.split(b"\0") if name})


def snapshot(label):
    scratch = ROOT / ".runtime" / "gate"
    scratch.mkdir(parents=True, exist_ok=True)
    target = Path(tempfile.mkdtemp(prefix="source-", dir=scratch))
    manifest = {}
    for name in candidates():
        source = ROOT / name
        if not source.exists() and not source.is_symlink():
            continue
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination, follow_symlinks=False)
        manifest[name] = hashlib.sha256(source.read_bytes()).hexdigest()
    (scratch / f"{target.name}.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (scratch / f"{label}-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    digest = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    print(f"{label} candidate source: {target} ({len(manifest)} files, {digest})", flush=True)
    return target


def parity():
    flake = json.loads((ROOT / "flake.lock").read_text())
    devenv = json.loads((ROOT / "devenv.lock").read_text())
    for lock in (flake, devenv):
        node = lock["nodes"][lock["root"]]["inputs"]["nixpkgs"]
        if not isinstance(node, str):
            raise RuntimeError("nixpkgs must have a direct locked input")
        identity = lock["nodes"][node]["locked"]
        if lock is flake:
            expected = identity
        elif identity != expected:
            raise RuntimeError("flake/devenv nixpkgs lock mismatch")
    version = subprocess.check_output(["nix", "--version"], text=True).strip()
    unit = Path(shutil.which("nix-unit") or "").resolve()
    if version != "nix (Nix) 2.35.1" or unit.parent.parent.name.split("-", 1)[-1] != "nix-unit-2.35.1":
        raise RuntimeError(f"toolchain mismatch: {version}; {unit}")
    print(f"toolchain: {version}; {unit}", flush=True)


def main():
    os.chdir(ROOT)
    mode, *selection = sys.argv[1:]
    if mode in ("format", "check-format"):
        if mode == "check-format":
            parity()
        files = [name for name in candidates() if name.endswith(".nix") and (ROOT / name).is_file()]
        if mode == "check-format":
            source = snapshot("check-format")
            files = [str(source / name) for name in files]
        run(["nixfmt", *(["--check"] if mode == "check-format" else []), *files])
    elif mode == "static":
        run(["statix", "check", str(snapshot("check-nix"))])
    elif mode == "prepare":
        parity()
        source = snapshot("prepare")
        system = subprocess.check_output(
            ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], text=True
        )
        reference = "path:" + str(source) + "#checks." + system
        names = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", reference, "--apply", "builtins.attrNames"], text=True
        ))
        store = subprocess.check_output(
            ["nix", "eval", "--raw", "--expr", "builtins.storeDir"], text=True
        )
        dependencies = set()
        for name in names:
            derivations = json.loads(subprocess.check_output(
                ["nix", "derivation", "show", reference + "." + name], text=True
            ))
            if derivations["version"] != 4:
                raise RuntimeError("unsupported derivation JSON version")
            for derivation in derivations["derivations"].values():
                for path, inputs in derivation["inputs"]["drvs"].items():
                    if inputs["dynamicOutputs"]:
                        raise RuntimeError("dynamic check dependencies are unsupported")
                    dependencies.add(store + "/" + path + "^" + ",".join(inputs["outputs"]))
        run(["nix", "build", "--no-link", *sorted(dependencies)])
    elif mode == "flake":
        parity()
        run([
            "nix", "--extra-experimental-features", "nix-command flakes pipe-operators",
            "flake", "check", "--offline", "--no-update-lock-file", "-L",
            "--option", "substituters", "", "--option", "fallback", "false",
            "--option", "builders", "", "--option", "sandbox", "true",
            "path:" + str(snapshot("gate-flake")),
        ])
    elif mode == "test":
        parity()
        source = snapshot("focused")
        system = subprocess.check_output(["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], text=True)
        expression = f'(builtins.getFlake {json.dumps("path:" + str(source))}).legacyPackages.{system}.qualification'
        args = ["nix-unit", "--option", "experimental-features", "nix-command flakes pipe-operators", "--impure", "--expr", expression]
        for path in selection:
            args.extend(["--attr", path])
        run(args)
    else:
        raise RuntimeError(f"unknown operation: {mode}")


if __name__ == "__main__":
    main()
