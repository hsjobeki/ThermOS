# passwd: name:x:uid:gid:gecos:home:shell
# group:  name:x:gid:members
# shadow: name:!:1:::::
{ types, ... }:
{
  name = "users-builder";

  subscribe = [
    "/contracts/users"
    "/contracts/groups"
  ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { subscriptions, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      users = subscriptions.users;
      groups = subscriptions.groups;

      # Sort by uid/gid for stable, readable output
      sortedUsers = builtins.sort (a: b: a.uid < b.uid) users;
      sortedGroups = builtins.sort (a: b: a.gid < b.gid) groups;

      passwdLine = u: "${u.name}:x:${toString u.uid}:${toString u.gid}:${u.gecos}:${u.home}:${u.shell}";

      groupLine = g: "${g.name}:x:${toString g.gid}:${builtins.concatStringsSep "," g.members}";

      # Locked account, no password aging
      shadowLine = u: "${u.name}:!:1::::::";

      passwdFile = pkgs.writeText "passwd" (lib.concatMapStringsSep "\n" passwdLine sortedUsers + "\n");
      groupFile = pkgs.writeText "group" (lib.concatMapStringsSep "\n" groupLine sortedGroups + "\n");
      shadowFile = pkgs.writeText "shadow" (lib.concatMapStringsSep "\n" shadowLine sortedUsers + "\n");
    in
    {
      derivation = pkgs.runCommand "thermos-users" { } ''
        mkdir -p $out/etc
        cp ${passwdFile} $out/etc/passwd
        cp ${groupFile} $out/etc/group
        cp ${shadowFile} $out/etc/shadow
      '';
    };
}
