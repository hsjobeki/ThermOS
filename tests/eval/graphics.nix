# Unit under test: /core/graphics impl (modules/core/graphics.nix). Asserts the
# GPU DRM drivers are published as (system, available) for udev modalias
# autoload, that /run/opengl-driver is published as a tmpfiles symlink to mesa
# (the userspace GL/GBM path cosmic-comp's KMS backend opens), and that the
# module is inert when disabled.
{ tree, ... }:
let
  inherit (builtins) all;
  km = opts: (tree.modules.core.modules.graphics opts)."kernel-modules";
  tmp = opts: (tree.modules.core.modules.graphics opts).tmpfiles;
in
{
  testDisabledEmpty = {
    expr = km { };
    expected = [ ];
  };

  testPublishesGpuModules = {
    expr = map (m: m.name) (km {
      enable = true;
    });
    expected = [
      "virtio_gpu"
      "i915"
      "amdgpu"
      "nouveau"
    ];
  };

  testAllSystemAvailable = {
    expr = all (m: m.stage == "system" && m.mode == "available") (km {
      enable = true;
    });
    expected = true;
  };

  testDisabledNoOpenglDriver = {
    expr = tmp { };
    expected = [ ];
  };

  # cosmic-comp's KMS backend opens /run/opengl-driver/lib/gbm/dri_gbm.so;
  # nixpkgs mesa hardcodes that path. The rule must symlink it to a mesa store
  # path so GBM/DRI resolve (without it: "Backend initialized without output").
  testPublishesOpenglDriver = {
    expr =
      let
        rules = map (t: t.rule) (tmp {
          enable = true;
        });
      in
      builtins.length rules == 1
      &&
        builtins.match "L\\+ /run/opengl-driver - - - - /nix/store/.*-mesa-.*" (builtins.head rules)
        != null;
    expected = true;
  };
}
