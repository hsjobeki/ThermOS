{
  entrypoint,
  tree,
  lib,
  ...
}:
{
  # Smoke test that treeery builder produces a derivation
  testEtcProducesDerivation = {
    expr = lib.isDerivation (tree.modules.builders.modules.etc { }).derivation;
    expected = true;
  };

  testPackagesProducesDerivation = {
    expr = lib.isDerivation (tree.modules.builders.modules.packages { }).derivation;
    expected = true;
  };

  testUnitsProducesDerivation = {
    expr = lib.isDerivation (tree.modules.builders.modules.units { }).derivation;
    expected = true;
  };

  testTmpfilesProducesDerivation = {
    expr = lib.isDerivation (tree.modules.builders.modules.tmpfiles { }).derivation;
    expected = true;
  };

  # toplevel produces a derivation
  testToplevelProducesDerivation = {
    expr = lib.isDerivation entrypoint.toplevel;
    expected = true;
  };

  testToplevelName = {
    expr = entrypoint.toplevel.name;
    expected = "thermos-system";
  };

  testRootfsProducesDerivation = {
    expr = lib.isDerivation entrypoint.rootfs;
    expected = true;
  };

  testRootfsName = {
    expr = entrypoint.rootfs.name;
    expected = "thermos-rootfs";
  };

  testUsersProducesDerivation = {
    expr = lib.isDerivation (tree.modules.builders.modules.users { }).derivation;
    expected = true;
  };

  testUsersName = {
    expr = (tree.modules.builders.modules.users { }).derivation.name;
    expected = "thermos-users";
  };
}
