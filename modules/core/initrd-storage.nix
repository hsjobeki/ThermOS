# Broad storage controller coverage for the initrd
# Off by default
# When enabled, publishes kernel modules as (initrd, available)
# So udev initrd autoloads whichever match the current hardware
# by modalias
{ types, ... }:
{
  name = "initrd-storage";

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
  };

  publish = [ "/contracts/kernel-modules" ];

  impl =
    { options, ... }:
    let
      # SCSI disk/cdrom plus controller transports; all carry modaliases udev
      # matches at coldplug.
      controllers = [
        "nvme"
        "ahci"
        "ata_piix"
        "sd_mod"
        "sr_mod"
        "virtio_scsi"
        "usb_storage"
        "uas"
        "xhci_pci"
        "ehci_pci"
      ];
    in
    {
      "kernel-modules" =
        if options.enable then
          map (name: {
            inherit name;
            stage = "initrd";
            mode = "available";
          }) controllers
        else
          [ ];
    };
}
