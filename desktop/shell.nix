{
  thermos ? import ../. { },
}:
let
  pkgs = thermos.pkgs;

  # Build/runtime native libs for the Slint desktop crates. The winit/femtovg
  # backend (Tier 2) dlopens libGL/EGL, fontconfig, freetype, libxkbcommon and
  # wayland; the software-renderer layer-shell backend (Tier 1) needs only
  # libwayland-client and libxkbcommon at runtime. fontconfig/freetype are also a
  # BUILD input: the Slint compiler's EmbedForSoftwareRenderer step locates a
  # system font to bake glyphs. Provide the superset in the dev shell.
  nativeLibs = with pkgs; [
    fontconfig
    freetype
    libxkbcommon
    wayland
    libGL
  ];
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    rustc
    cargo
    pkg-config
  ];
  buildInputs = nativeLibs;

  # Harness tools: a nested wlroots compositor (advertises zwlr_layer_shell_v1 AND
  # ext-foreign-toplevel-list-v1, unlike a host GNOME session), a terminal to make
  # toplevels, a protocol inspector, a screenshotter, and dbus for the D-Bus source
  # acceptance test.
  packages = with pkgs; [
    sway
    foot
    wayland-utils
    grim
    dbus
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath nativeLibs;

  # Build-time font discovery for the embed step. With EmbedForSoftwareRenderer the
  # runtime needs no fontconfig (glyphs are baked into the binary); this var is read
  # by the Slint compiler during `cargo build` to find DejaVu for embedding.
  FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };

  # Sentinel the harness scripts check before re-entering this shell. Do NOT switch
  # to IN_NIX_SHELL: this repo's direnv drops you in the thermos ROOT shell, which
  # sets IN_NIX_SHELL but ships no rust toolchain.
  DESKTOP_NIX_SHELL = "1";
}
