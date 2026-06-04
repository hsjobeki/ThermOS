let
  thermos = import ./. { };
  pkgs = thermos.pkgs;
in
pkgs.mkShell {
  packages = [
    pkgs.treefmt
    pkgs.nixfmt
  ];
}
