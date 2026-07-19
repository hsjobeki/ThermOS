# Nix derivations for the ThermOS desktop crates, built from the workspace with
# the pinned nixpkgs toolchain (one source of truth: callers pass `pkgs` from the
# thermos tree, never a fresh channel). Each component is its own derivation so a
# headless system that only needs the daemon does not drag the GUI binaries' libs
# into its closure. They share one vendored Cargo.lock (the vendor dir is a
# content-addressed fixed-output derivation, so the fetch is shared across them).
{ pkgs }:
let
  # Exclude the build output directory so the source hash is stable and the copy
  # is small.
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      base != "target";
    name = "thermos-desktop-src";
  };

  common = {
    version = "0.0.0";
    inherit src;
    cargoLock.lockFile = ./Cargo.lock;
    # The whole-workspace test build would pull every member (and slint); each
    # component derivation builds only its own binary's dependency tree.
    doCheck = false;
  };

  # The Slint winit/femtovg backend dlopens these at runtime; fontconfig/freetype
  # are also a build input (the glyph step locates a system font). All from the
  # pinned nixpkgs.
  guiBuildInputs = with pkgs; [
    fontconfig
    freetype
    libxkbcommon
    wayland
    libGL
  ];
  fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
in
{
  # The system update authority. No Slint, so no GUI native libs.
  daemon = pkgs.rustPlatform.buildRustPackage (
    common
    // {
      pname = "thermos-daemon";
      cargoBuildFlags = [
        "--bin"
        "thermos-daemon"
      ];
      nativeBuildInputs = [ pkgs.pkg-config ];
      # Ship the Polkit action definitions in the package's share/polkit-1/actions.
      # The rootfs merges share/polkit-1 from the packages env, so polkitd (datadir
      # /usr/share) finds this action alongside the stock freedesktop ones.
      postInstall = ''
        install -Dm644 daemon/org.thermos.daemon.policy \
          $out/share/polkit-1/actions/org.thermos.daemon.policy
      '';
    }
  );

  # The desktop UI binaries: the Tier 2 settings window (winit) and the Tier 1
  # dock + top bars (layer-shell software renderer). Built together so slint and
  # the Wayland stack compile once and all three share one output. The bars embed
  # their glyphs at build time (EmbedForSoftwareRenderer); slint's compiler resolves
  # sans-serif from SLINT_DEFAULT_FONT, not fontconfig, so it is pinned to DejaVu Sans
  # here (works in the sandbox, which has no system fonts). FONTCONFIG_FILE feeds the
  # settings window's fontconfig.
  apps = pkgs.rustPlatform.buildRustPackage (
    common
    // {
      pname = "thermos-desktop-apps";
      cargoBuildFlags = [
        "--bin"
        "settings"
        "--bin"
        "dock"
        "--bin"
        "top"
      ];
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = guiBuildInputs;
      FONTCONFIG_FILE = fontsConf;
      SLINT_DEFAULT_FONT = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf";
      # shell-runtime carries the shutdown/concurrency core (idempotent trigger,
      # register-after-fire, the swap-before-lock race invariant). Its unit tests are
      # headless (the Slint quit action is injected), so run them here, where
      # shell-runtime and slint are already compiled for the bars. Scoped to
      # -p shell-runtime: the bin crates have no tests and would need a display.
      doCheck = true;
      cargoTestFlags = [
        "-p"
        "shell-runtime"
      ];
    }
  );
}
