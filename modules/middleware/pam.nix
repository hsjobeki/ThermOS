# Subscribes to /contracts/pam, publishes to /contracts/etc.
# Resolves PAM module names to absolute store paths.
{ types, ... }:
{
  name = "pam";

  subscribe = [ "/contracts/pam" ];
  publish = [ "/contracts/etc" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { subscriptions, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;

      # NixOS patches pam_unix to hardcode /run/wrappers/bin/unix_chkpwd,
      # a setuid wrapper that doesn't exist outside NixOS. Remove the patch
      # so pam_unix uses the default unix_chkpwd from its own store path.
      pam = pkgs.pam.overrideAttrs { postPatch = ""; };

      modulePackages = {
        pam_unix = pam;
        pam_deny = pam;
        pam_permit = pam;
        pam_env = pam;
        pam_loginuid = pam;
        pam_keyinit = pam;
        pam_umask = pam;
        pam_limits = pam;
        pam_nologin = pam;
        pam_securetty = pam;
        pam_shells = pam;
        pam_warn = pam;
        pam_systemd = pkgs.systemd;
      };

      resolveModule =
        rule:
        let
          pkg =
            if rule ? package then
              rule.package
            else if modulePackages ? ${rule.module} then
              modulePackages.${rule.module}
            else
              throw "PAM middleware: unknown module '${rule.module}'. Provide a 'package' field.";
        in
        "${pkg}/lib/security/${rule.module}.so";

      renderRule =
        rule:
        let
          path = resolveModule rule;
          suffix = if rule ? args then " ${rule.args}" else "";
        in
        "${rule.type} ${rule.control} ${path}${suffix}";

      renderService = service: builtins.concatStringsSep "\n" (map renderRule service.rules) + "\n";
    in
    {
      etc = map (service: {
        name = "pam.d/${service.name}";
        text = renderService service;
      }) subscriptions.pam;
    };
}
