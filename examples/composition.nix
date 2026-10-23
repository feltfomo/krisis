{ lib, fx }:
let
  k = import ../src { inherit lib fx; };
  check =
    code: type: value:
    k.validation.check { inherit code type; } value;
  T = k.validation.types;
in
{
  independent = k.report.run { } (
    k.validation.all [
      (check "port" T.Int false)
      (check "name" T.String 1)
    ]
  );
  dependent = k.report.run { } (
    k.validation.andThen (_: throw "dependent work must be skipped") (check "port" T.Int false)
  );
}
