(import ../default.nix {
  options = {
    "/services/openssh" = {
      authorizedKeys = {
        root = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLuev3+8kF+pd1YnCRR7Kw9i9DswOMvGhvdQq6dEIJF johannes@hsjobeki"
        ];
      };
    };
  };
}).rootfs
