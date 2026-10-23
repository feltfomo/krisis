{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  emit =
    code:
    k.report.emit {
      inherit code;
      message = "notice";
      severity = "warning";
    };
in
k.report.run { } (
  k.report.withContext { primary.source = "service.nix"; } (
    fx.bind (emit "outer") (
      _: fx.bind (k.report.withContext { primary.label = "nested"; } (emit "inner")) (_: emit "restored")
    )
  )
)
