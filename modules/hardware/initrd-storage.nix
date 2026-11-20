# Broad storage controller coverage for the initrd.
# Publishes kernel modules as (initrd, available), so udev initrd autoloads
# whichever match the current hardware by modalias.
{ ... }:
{
  name = "initrd-storage";

  publish = [ "/contracts/kernel-modules" ];

  impl =
    { ... }:
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
      "kernel-modules" = map (name: {
        inherit name;
        stage = "initrd";
        mode = "available";
      }) controllers;
    };
}
