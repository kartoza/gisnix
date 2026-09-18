{ mkTest, ... }:
{
  # NOTE: hosts that need Internet access must be run with
  # '--option sandbox relaxed --builders ""' to enable Internet access.

  example = mkTest "example";
}
