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

  testSshdPatternIntegration = {
    expr =
      let
        # What openssh would publish
        sshdRules = [
          {
            name = "sshd";
            rules = [
              {
                type = "auth";
                control = "required";
                module = "pam_unix";
                args = "nullok";
              }
              {
                type = "account";
                control = "required";
                module = "pam_unix";
              }
              {
                type = "session";
                control = "required";
                module = "pam_unix";
              }
              {
                type = "session";
                control = "optional";
                module = "pam_loginuid";
              }
            ];
          }
        ];
        # What base publishes
        baseRules = (tree.modules.core.modules.base { }).pam;
        # Merge like the contract would
        merged = pamContract.merge {
          base = baseRules;
          openssh = sshdRules;
        };
        # Verify sshd is in the merged set
        sshdService = head (filter (s: s.name == "sshd") merged);
      in
      {
        totalServices = length merged;
        sshdRuleCount = length sshdService.rules;
        firstModule = (head sshdService.rules).module;
      };
    expected = {
      totalServices = 5;
      sshdRuleCount = 4;
      firstModule = "pam_unix";
    };
  };
}
