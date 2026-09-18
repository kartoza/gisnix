# Stable kernel: whatever the pinned nixpkgs calls default.
#
# Deliberately empty. NixOS already boots its default kernel, and OpenZFS from
# the same nixpkgs is guaranteed to match it — nixpkgs marks an incompatible
# kernel/ZFS pair broken at evaluation, so this arrangement cannot produce a
# machine that boots but cannot import its pool.
#
# The file exists so the choice has two visible sides in `kz configure`.
# "Leave the option unset" is not something anyone can see in a menu.
{ ... }:
{
}
