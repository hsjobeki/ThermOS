{
  entrypoint,
  tree,
  nixpkgs-lib,
  ...
}:
{
  # Smoke test that treeery builder produces a derivation
  testEtcProducesDerivation = {
    expr = nixpkgs-lib.isDerivation (tree.modules.builders.modules.etc { }).derivation;
    expected = true;
  };

  testPackagesProducesDerivation = {
    expr = nixpkgs-lib.isDerivation (tree.modules.builders.modules.packages { }).derivation;
    expected = true;
  };

  testUnitsProducesDerivation = {
    expr = nixpkgs-lib.isDerivation (tree.modules.builders.modules.units { }).derivation;
    expected = true;
  };

  testTmpfilesProducesDerivation = {
    expr = nixpkgs-lib.isDerivation (tree.modules.builders.modules.tmpfiles { }).derivation;
    expected = true;
  };

  testUsersProducesDerivation = {
    expr = nixpkgs-lib.isDerivation (tree.modules.builders.modules.users { }).derivation;
    expected = true;
  };

  testUsersName = {
    expr = (tree.modules.builders.modules.users { }).derivation.name;
    expected = "thermos-users";
  };
}
