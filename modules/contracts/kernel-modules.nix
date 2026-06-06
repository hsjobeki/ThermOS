# Publishers provide [{ name, stage, mode }] records.
#
#   name  :: str    kernel module name (e.g. "af_packet")
#   stage :: enum   "initrd" | "system"    (when the module is loaded)
#   mode  :: enum   "force"  | "available" (force-load, or present for udev autoload)
#
# Four quadrants:
#   (initrd, force)     boot.initrd.kernelModules     -> initrd init modprobe
#   (initrd, available) boot.initrd.availableKernelModules -> udev in initrd (unsupported here)
#   (system, force)     boot.kernelModules            -> systemd-modules-load
#   (system, available) implicit module tree          -> systemd-udevd modalias autoload
{ types, ... }:
{
  name = "kernel-modules";

  options = {
    name = {
      type = types.str;
    };
    stage = {
      type = types.enum "stage" [
        "initrd"
        "system"
      ];
    };
    mode = {
      type = types.enum "mode" [
        "force"
        "available"
      ];
    };
  };

  contract = {
    merge =
      publishers:
      let
        /*
          Example 'publishers'
          {
           "/core/initrd-network" = [ { name = "af_packet"; stage = "initrd"; mode = "force"; } ];
           "/services/foo"        = [ { name = "loop"; stage = "system"; mode = "force"; } ];
          }

          Collect all records into a flat list:

          [
            { name = "af_packet"; stage = "initrd"; mode = "force"; }
            { name = "loop"; stage = "system"; mode = "force"; }
          ]
        */
        all = builtins.concatLists (builtins.attrValues publishers);
        key = m: "${m.name}\t${m.stage}\t${m.mode}";
      in
      builtins.attrValues (
        # Use listToAttrs to deduplicate (name,stage,mode) triplets
        builtins.listToAttrs (
          map (m: {
            name = key m;
            value = m;
          }) all
        )
      );
  };

  impl = { options, ... }: options;
}
