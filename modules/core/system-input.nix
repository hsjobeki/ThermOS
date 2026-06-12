# Input device drivers for the running system: keyboard, pointer, HID.
# Off by default. When enabled, publishes (system, *) to /contracts/kernel-modules.
#
# The PS/2 path is force-loaded: i8042 self-probes a legacy controller that has no
# modalias for udev to match; atkbd binds the keyboard serio port it creates; evdev
# is an input handler with no device of its own. USB and I2C HID (and the PS/2 aux
# port psmouse binds) autoload by device modalias. serio/libps2 come in as
# depmod-resolved dependencies of the closure.
{ types, ... }:
{
  name = "system-input";

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
      # No reliable modalias autoload: force-load via systemd-modules-load.
      force = [
        "i8042"
        "atkbd"
        "evdev"
      ];
      # udev autoloads by device modalias (USB, I2C-HID, the PS/2 aux serio port).
      available = [
        "usbhid"
        "hid_generic"
        "i2c_hid_acpi"
        "hid_multitouch"
        "psmouse"
      ];
    in
    {
      "kernel-modules" =
        if options.enable then
          (map (name: {
            inherit name;
            stage = "system";
            mode = "force";
          }) force)
          ++ (map (name: {
            inherit name;
            stage = "system";
            mode = "available";
          }) available)
        else
          [ ];
    };
}
