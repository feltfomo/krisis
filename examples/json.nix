{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  report = k.report.run { } (
    fx.bind (k.report.emit {
      code = "notice";
      severity = "warning";
      message = "check the port";
      context = throw "private context";
    }) (_: fx.pure { payload = throw "application value"; })
  );
in
k.render.jsonReport report
