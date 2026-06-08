{ tree, ... }:
let
  types = tree.types;
  unitsContract = (import ../../modules/contracts/units.nix { inherit types; }).contract;
  inherit (builtins) hasAttr;
in
{
  testUnitsBuilderName = {
    expr = (tree.modules.builders.modules.units { }).derivation.name;
    expected = "thermos-units";
  };

  # proves data flows: module -> contract -> merged
  testMergedUnitsContainGetty = {
    expr =
      let
        gettyUnits = (tree.modules.services.modules.getty { }).units;
        merged = unitsContract.merge { getty = gettyUnits; };
      in
      hasAttr "getty@tty1.service" merged;
    expected = true;
  };

  testMergedGettyHasServiceSection = {
    expr =
      let
        gettyUnits = (tree.modules.services.modules.getty { }).units;
        merged = unitsContract.merge { getty = gettyUnits; };
      in
      hasAttr "Service" merged."getty@tty1.service";
    expected = true;
  };
}
