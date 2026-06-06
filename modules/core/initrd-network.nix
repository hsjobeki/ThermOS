# Initrd networking support, the boot.initrd.network.enable analog.
#
# When enabled, declares that networking kernel modules must be force-loaded in
# the initrd so the running system inherits them across switch_root. Today that
# is af_packet: the AF_PACKET socket family that systemd-networkd's DHCP and
# LLDP clients open. The kernel ships it as a module (CONFIG_PACKET=m), so
# without an explicit load socket(AF_PACKET) returns EAFNOSUPPORT and DHCP
# silently fails.
#
# Independent of /services/networkd (the daemon). This toggles the early-boot
# capability; networkd consumes it at runtime.
{ types, ... }:
{
  name = "initrd-network";

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
  };

  publish = [ "/contracts/kernel-modules" ];

  impl =
    { options, ... }:
    {
      "kernel-modules" =
        if options.enable then
          [
            {
              name = "af_packet";
              stage = "initrd";
              mode = "force";
            }
          ]
        else
          [ ];
    };
}
