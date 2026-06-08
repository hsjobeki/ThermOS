{ tree, lib, ... }:
let
  inherit (builtins) all head match;
  inherit (lib) isDerivation;
in
{
  testDhcpNetworkFile = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
        };
        etc = head impl.etc;
      in
      {
        inherit (etc) name;
        hasDHCP = match ".*DHCP=yes.*" etc.text != null;
      };
    expected = {
      name = "systemd/network/80-wired.network";
      hasDHCP = true;
    };
  };

  testStaticAddress = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
          useDHCP = false;
          addresses = [ "192.168.1.2/24" ];
        };
        etc = head impl.etc;
      in
      {
        inherit (etc) name;
        hasAddress = match ".*Address=192\\.168\\.1\\.2/24.*" etc.text != null;
        noDHCP = match ".*DHCP=yes.*" etc.text == null;
      };
    expected = {
      name = "systemd/network/80-wired.network";
      hasAddress = true;
      noDHCP = true;
    };
  };

  testDisabledEmpty = {
    expr =
      let
        impl = tree.modules.services.modules.networkd { };
      in
      {
        inherit (impl) etc users groups;
      };
    expected = {
      etc = [ ];
      users = [ ];
      groups = [ ];
    };
  };

  testNetworkUser = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
        };
      in
      (head impl.users).name;
    expected = "systemd-network";
  };

  testDhcpAssertionsPass = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
          useDHCP = true;
        };
      in
      all (a: a.assertion) impl.assertions;
    expected = true;
  };

  testStaticAssertionsPass = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
          useDHCP = false;
          addresses = [ "192.168.1.2/24" ];
        };
      in
      all (a: a.assertion) impl.assertions;
    expected = true;
  };

  testNoAddressAssertionFails = {
    expr =
      let
        impl = tree.modules.services.modules.networkd {
          enable = true;
          useDHCP = false;
          addresses = [ ];
        };
      in
      all (a: a.assertion) impl.assertions;
    expected = false;
  };

  testDisabledNoAssertions = {
    expr = (tree.modules.services.modules.networkd { }).assertions;
    expected = [ ];
  };

  testTreeAcceptsDhcp = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/services/networkd" = {
              enable = true;
              useDHCP = true;
            };
          };
        };
      in
      isDerivation (reconfigured.modules.builders.modules.toplevel { }).derivation;
    expected = true;
  };
}
