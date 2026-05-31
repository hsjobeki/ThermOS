{ types, ... }:
{
  name = "toplevel";

  subscribe = [ "/contracts/assertions" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
    etcBuilder = {
      path = "/builders/etc";
    };
    packagesBuilder = {
      path = "/builders/packages";
    };
    unitsBuilder = {
      path = "/builders/units";
    };
    tmpfilesBuilder = {
      path = "/builders/tmpfiles";
    };
    usersBuilder = {
      path = "/builders/users";
    };
  };

  impl =
    {
      inputs,
      results,
      subscriptions,
      ...
    }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;

      assertions = subscriptions.assertions;
      failedAssertions = builtins.filter (a: !a.assertion) assertions;
      assertionCheck =
        if failedAssertions != [ ] then
          throw (lib.concatMapStringsSep "\n" (a: "Assertion failed: ${a.message}") failedAssertions)
        else
          true;
    in
    assert assertionCheck;
    {
      builders = {
        etc = results.etcBuilder.derivation;
        packages = results.packagesBuilder.derivation;
        units = results.unitsBuilder.derivation;
        tmpfiles = results.tmpfilesBuilder.derivation;
        users = results.usersBuilder.derivation;
      };

      derivation = pkgs.runCommand "thermos-system" { } ''
        mkdir -p $out

        ln -s ${results.etcBuilder.derivation} $out/etc
        ln -s ${results.packagesBuilder.derivation} $out/sw
        ln -s ${results.unitsBuilder.derivation}/etc/systemd $out/systemd
        ln -s ${results.tmpfilesBuilder.derivation}/etc/tmpfiles.d $out/tmpfiles.d
        ln -s ${results.usersBuilder.derivation} $out/users
      '';
    };
}
