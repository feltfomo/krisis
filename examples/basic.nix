{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  T = k.validation.types;
  port = T.refined "Port" T.Int (n: n > 0 && n < 65536);
  check = k.validation.check {
    type = T.Record {
      ports = T.ListOf port;
      payload = T.Any;
    };
    code = "service/shape";
    location.source = "caller-supplied.nix";
  };
in
k.report.run { } (
  k.validation.andThen (value: fx.pure value.ports) (check {
    ports = [
      8080
      (-1)
    ];
    payload = throw "opaque application data";
  })
)
