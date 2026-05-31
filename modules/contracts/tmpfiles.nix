# Publishers provide [{ rule }] records.
#
# { rule :: str }
#
# Each rule is a tmpfiles.d line (e.g. "d /run/dbus 0755 root root -").
# Merge: concatenation. Conflicts handled by systemd-tmpfiles itself.
{ types, ... }:
{
  name = "tmpfiles";

  options = {
    rule = {
      type = types.str;
    };
  };

  contract = {
    merge = publishers: builtins.concatLists (builtins.attrValues publishers);
  };

  impl = { options, ... }: options;
}
