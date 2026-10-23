{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  config = {
    port = 8080;
    unrelated = throw "unused config";
  };
  # origin lookup belongs to the caller and may have no result
  pos = builtins.unsafeGetAttrPos "port" config;
  report = k.report.run { } (
    k.validation.check {
      type = k.validation.types.Int;
      code = "service/port";
      location = {
        source = "service-config.nix";
        path = [ (k.path.field "port") ];
      }
      // lib.optionalAttrs (pos != null) {
        source = pos.file;
        range = {
          start = { inherit (pos) line column; };
          end = { inherit (pos) line column; };
        };
      };
    } config.port
  );
in
k.nix.module report
