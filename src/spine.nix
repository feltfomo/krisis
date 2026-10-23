{
  count,
  head,
  project,
}:
let
  cursors = builtins.genList (
    index: if index == 0 then head else (builtins.elemAt cursors (index - 1)).previous
  ) count;
  # force each cursor after its predecessor, so reverse access can't build a descent chain
  traversed = builtins.foldl' (unit: cursor: builtins.seq cursor unit) null cursors;
in
builtins.seq traversed (
  builtins.genList (index: project (builtins.elemAt cursors (count - index - 1))) count
)
