{ types, ... }:
{
  name = "networkd";

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
    useDHCP = {
      type = types.bool;
      default = true;
    };
    addresses = {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  publish = [
    "/contracts/etc"
    "/contracts/users"
    "/contracts/groups"
    "/contracts/assertions"
  ];

  impl =
    { options, ... }:
    let
      networkSection =
        if options.useDHCP then
          "DHCP=yes"
        else
          builtins.concatStringsSep "\n" (map (a: "Address=${a}") options.addresses);

      networkFile = ''
        [Match]
        Type=ether

        [Network]
        ${networkSection}
        LLDP=no
        EmitLLDP=no
      '';
    in
    if !options.enable then
      {
        etc = [ ];
        users = [ ];
        groups = [ ];
        assertions = [ ];
      }
    else
      {
        # Stock systemd-networkd.service runs as User=systemd-network.
        # The rootfs builder enables the stock unit via .wants symlink
        # when /etc/systemd/network/ exists.
        users = [
          {
            name = "systemd-network";
            uid = 80;
            gid = 80;
            home = "/";
            shell = "/bin/nologin";
            gecos = "systemd Network Management";
          }
        ];

        groups = [
          {
            name = "systemd-network";
            gid = 80;
          }
        ];

        etc = [
          {
            name = "systemd/network/80-wired.network";
            text = networkFile;
          }
        ];
        # We do not yet support dhcp.
        # Therefore static-ip needs to be configured.
        # TODO: Adopt these assertions, when dhcp support is added
        assertions = [
          {
            assertion = options.useDHCP || options.addresses != [ ];
            message = "networkd: addresses must be statically configured when dhcp is disabled";
          }
          {
            assertion = !options.useDHCP;
            message = "networkd: dhcp is not yet implemented";
          }
        ];
      };
}
