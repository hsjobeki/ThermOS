# Broad GPU coverage for the running system (stage 2).
# Off by default. When enabled, publishes the DRM/KMS drivers as
# (system, available) so systemd-udevd autoloads whichever matches the GPU
# present, by modalias, and points /run/opengl-driver at mesa so the userspace
# GL/GBM stack resolves. cosmic-comp's KMS backend needs both.
# simpledrm is built into the kernel (CONFIG_DRM_SIMPLEDRM=y) as a no-driver
# fallback and needs no module.
#
# Firmware: i915/amdgpu/nouveau want device firmware for full function (the
# linux-firmware roadmap item); the modules still load and drive basic KMS
# without it. virtio_gpu (QEMU) needs none.
{ types, ... }:
{
  name = "graphics";

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
  };

  publish = [
    "/contracts/kernel-modules"
    "/contracts/tmpfiles"
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      # DRM drivers shipped as modules (=m) by the pinned kernel: virtio_gpu for
      # QEMU, the common metal GPU families otherwise. Each carries PCI
      # modaliases udev matches at coldplug, so only the present GPU loads.
      drivers = [
        "virtio_gpu"
        "i915"
        "amdgpu"
        "nouveau"
      ];
    in
    {
      "kernel-modules" =
        if options.enable then
          map (name: {
            inherit name;
            stage = "system";
            mode = "available";
          }) drivers
        else
          [ ];

      # nixpkgs mesa hardcodes /run/opengl-driver/lib as its loader search path
      # (DRI, GBM, EGL, Vulkan). cosmic-comp's KMS backend opens
      # /run/opengl-driver/lib/gbm/dri_gbm.so; without it GBM init on
      # /dev/dri/card0 fails and the compositor exits "Backend initialized
      # without output". Point it at the mesa the desktop is built against.
      tmpfiles =
        if options.enable then [ { rule = "L+ /run/opengl-driver - - - - ${pkgs.mesa}"; } ] else [ ];
    };
}
