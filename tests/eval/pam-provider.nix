{ tree, ... }:
let
  types = tree.types;
  pamContract = (import ../../modules/contracts/pam.nix { inherit types; }).contract;
  inherit (builtins)
    filter
    head
    length
    match
    ;
in
{
  testBasePublishesPam = {
    expr =
      let
        impl = tree.modules.core.modules.base { };
      in
      map (s: s.name) impl.pam;
    expected = [
      "login"
      "su"
      "other"
      "systemd-user"
    ];
  };

  testMiddlewareRendersEtc = {
    expr =
      let
        impl = tree.modules.middleware.modules.pam { };
        loginEntry = head (filter (e: e.name == "pam.d/login") impl.etc);
      in
      match ".*pam_unix\\.so.*" loginEntry.text != null;
    expected = true;
  };

  testMiddlewareResolvesStorePaths = {
    expr =
      let
        impl = tree.modules.middleware.modules.pam { };
        loginEntry = head (filter (e: e.name == "pam.d/login") impl.etc);
      in
      match ".*/nix/store/[a-z0-9]+-linux-pam[^/]*/lib/security/pam_unix\\.so.*" loginEntry.text != null;
    expected = true;
  };

  testMiddlewareRendersFiveServices = {
    expr =
      let
        impl = tree.modules.middleware.modules.pam { };
      in
      length impl.etc;
    expected = 5;
  };

  # unit: contracts/pam merge
  testSshdPatternIntegration = {
    expr =
      let
        sshdPublished = (tree.modules.services.modules.openssh { }).pam;
        merged = pamContract.merge {
          base = (tree.modules.core.modules.base { }).pam;
          openssh = sshdPublished;
        };
        sshdMerged = head (filter (s: s.name == "sshd") merged);
      in
      {
        names = map (s: s.name) merged;
        sshdRulesPreserved = sshdMerged.rules == (head sshdPublished).rules;
      };
    expected = {
      names = [
        "login"
        "su"
        "other"
        "systemd-user"
        "sshd"
      ];
      sshdRulesPreserved = true;
    };
  };
}
