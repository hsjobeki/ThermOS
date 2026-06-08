{ tree, ... }:
let
  inherit (builtins)
    all
    filter
    head
    length
    match
    ;
in
{
  testUser = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
      in
      head impl.users;
    expected = {
      name = "sshd";
      uid = 74;
      gid = 74;
      home = "/var/empty";
      shell = "/bin/nologin";
      gecos = "SSH privilege separation user";
      hashedPassword = "!";
    };
  };

  testGroup = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
      in
      head impl.groups;
    expected = {
      name = "sshd";
      gid = 74;
      members = [ ];
    };
  };

  testServiceUnit = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        unit = head (filter (u: u.unitName == "sshd.service") impl.units);
      in
      unit.unitConfig.Service.Type;
    expected = "simple";
  };

  testKeygenUnit = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        unit = head (filter (u: u.unitName == "sshd-keygen-ed25519.service") impl.units);
      in
      unit.unitConfig.Service.Type;
    expected = "oneshot";
  };

  testKeygenOrdering = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        unit = head (filter (u: u.unitName == "sshd-keygen-ed25519.service") impl.units);
      in
      unit.unitConfig.Unit.Before;
    expected = [ "sshd-keygen.target" ];
  };

  testKeygenTarget = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        units = map (u: u.unitName) impl.units;
      in
      all (n: builtins.elem n units) [
        "sshd.service"
        "sshd-keygen.target"
        "sshd-keygen-ed25519.service"
      ];
    expected = true;
  };

  testDefaultPort = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
      in
      match ".*Port 22.*" cfg.text != null;
    expected = true;
  };

  testCustomPort = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/services/openssh" = {
              port = 2222;
            };
          };
        };
        impl = (reconfigured.modules.services.modules.openssh { });
        cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
      in
      match ".*Port 2222.*" cfg.text != null;
    expected = true;
  };

  testPermitRootLogin = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
      in
      match ".*PermitRootLogin prohibit-password.*" cfg.text != null;
    expected = true;
  };

  testPam = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        svc = head impl.pam;
      in
      svc.name;
    expected = "sshd";
  };

  testPamRules = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        svc = head impl.pam;
      in
      map (r: r.type) svc.rules;
    expected = [
      "auth"
      "account"
      "session"
    ];
  };

  testPackage = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
      in
      length impl.packages;
    expected = 1;
  };

  testAuthorizedKeysRendered = {
    expr =
      let
        reconfigured = tree.override {
          options = {
            "/services/openssh" = {
              authorizedKeys = {
                root = [ "ssh-ed25519 AAAA testkey" ];
              };
            };
          };
        };
        impl = (reconfigured.modules.services.modules.openssh { });
        entry = head (filter (e: e.name == "ssh/authorized_keys/root") impl.etc);
      in
      entry.text;
    expected = "ssh-ed25519 AAAA testkey\n";
  };

  testNoAuthorizedKeysDefault = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
      in
      length (filter (e: match "ssh/authorized_keys/.*" e.name != null) impl.etc);
    expected = 0;
  };

  testHostKeys = {
    expr =
      let
        impl = tree.modules.services.modules.openssh { };
        cfg = head (filter (e: e.name == "ssh/sshd_config") impl.etc);
      in
      all (t: match ".*HostKey /var/lib/ssh/ssh_host_${t}_key.*" cfg.text != null) [
        "ed25519"
      ];
    expected = true;
  };
}
