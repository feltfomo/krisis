{ lib }:
root:
let
  excluded = map (line: lib.removeSuffix "/" (lib.removePrefix "/" line)) (
    lib.filter (line: line != "") (lib.splitString "\n" (builtins.readFile (root + "/.gitignore")))
  );
in
lib.cleanSourceWith {
  src = root;
  filter =
    path: _type:
    let
      relative = lib.removePrefix "${toString root}/" (toString path);
    in
    !(
      relative == ".git"
      || lib.hasPrefix ".git/" relative
      || lib.any (name: relative == name || lib.hasPrefix "${name}/" relative) excluded
    );
}
