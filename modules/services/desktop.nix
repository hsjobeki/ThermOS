{ types, ... }:
{
  name = "desktop";

  options = {
    enable = {
      type = types.bool;
      default = false;
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  publish = [
    "/contracts/packages"
    "/contracts/units"
    "/contracts/etc"
  ];

  impl =
    { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      apps = (import ../../desktop { inherit pkgs; }).apps;
      compositor = pkgs.cosmic-comp;

      # Runtime fontconfig for the bars: slint's femtovg renderer (linked via the
      # shared backend-winit feature) inits fontconfig at startup. Point it at
      # DejaVu so it does not error on the missing system config.
      fontsConf = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };

      # Pin floating-by-default declaratively (the reason cosmic-comp was chosen)
      # so an upstream default change cannot silently flip it. Shipped at the
      # cosmic-config system path under /usr/share/cosmic (XDG_DATA_DIRS), which
      # the rootfs exposes. cosmic-config falls back to compiled defaults on any
      # read error, so this is safe.
      cosmicConfig = pkgs.writeTextDir "share/cosmic/com.system76.CosmicComp/v1/autotile" "false";

      # Session launcher (approach A: no cosmic-session). cosmic-comp run
      # standalone skips systemd/session IPC (it has no COSMIC_SESSION_SOCK), so
      # this wrapper does the wiring itself: launch the compositor, discover the
      # Wayland socket it creates, publish WAYLAND_DISPLAY to the per-user systemd
      # manager, then start thermos-session.target. That binds graphical-session.target
      # via their graphical-session.target.wants symlinks. When cosmic-comp exits
      # the session ends and the target is torn down. --no-xwayland keeps the
      # closure Wayland-only (our clients are native); X app support is a later
      # increment.
      thermosSession = pkgs.writeShellApplication {
        name = "thermos-session";
        runtimeInputs = [
          compositor
          pkgs.systemd
          pkgs.coreutils
        ];
        text = ''
          : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
          export XDG_RUNTIME_DIR

          # Point mesa at its DRI drivers and EGL vendor (the NixOS
          # /run/opengl-driver convention, expressed as env). The vendor JSON
          # carries an absolute libEGL path and nixpkgs bakes RPATH, so no
          # LD_LIBRARY_PATH is needed (which would shadow cosmic-comp's libwayland).
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export __EGL_VENDOR_LIBRARY_DIRS="${pkgs.mesa}/share/glvnd/egl_vendor.d"

          # Cursor theme for the compositor: cosmic-comp loads the X cursor named
          # by XCURSOR_THEME, searched in XCURSOR_PATH. Without these it logs
          # NoDefaultCursor and draws an oversized fallback cursor.
          export XCURSOR_THEME="capitaine-cursors"
          export XCURSOR_PATH="${pkgs.capitaine-cursors}/share/icons"

          # Capture this launcher and cosmic-comp's output so a failed start is
          # debuggable from any shell; the compositor still renders to its DRM
          # device regardless of stdout.
          exec >>/tmp/thermos-session.log 2>&1
          echo "thermos-session: $(date -u +%FT%TZ) starting (XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR)"

          # Launch cosmic-comp and wait for the wayland socket it creates. Sets
          # the globals $comp + $display on success; returns 1 if the compositor
          # dies before a socket appears.
          start_comp() {
            local before="" s name
            for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
              case "$s" in *.lock) continue ;; esac
              [ -S "$s" ] && before="$before $(basename "$s")"
            done
            cosmic-comp --no-xwayland &
            comp=$!
            echo "thermos-session: launched cosmic-comp pid $comp"
            display=""
            for _ in $(seq 1 100); do
              for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
                case "$s" in *.lock) continue ;; esac
                [ -S "$s" ] || continue
                name=$(basename "$s")
                case " $before " in *" $name "*) continue ;; esac
                display="$name"
                break
              done
              [ -n "$display" ] && break
              kill -0 "$comp" 2>/dev/null || return 1
              sleep 0.1
            done
            [ -n "$display" ]
          }

          # Hardware GL first; if the compositor cannot initialize it (e.g. a VM
          # with no working virgl) fall back to mesa software rendering. The
          # fallback only runs on failure, so a working GPU pays nothing for it.
          if ! start_comp; then
            echo "thermos-session: hardware GL failed; retrying with software rendering" >&2
            export LIBGL_ALWAYS_SOFTWARE=1
            if ! start_comp; then
              echo "thermos-session: cosmic-comp could not create a socket (hardware and software)" >&2
              exit 1
            fi
          fi

          export WAYLAND_DISPLAY="$display"
          echo "thermos-session: WAYLAND_DISPLAY=$display; wiring the user graphical session"
          systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR || echo "thermos-session: import-environment FAILED"
          systemctl --user start thermos-session.target || echo "thermos-session: start thermos-session.target FAILED"

          wait "$comp" || true
          systemctl --user stop thermos-session.target || true
        '';
      };

      # On-demand launcher for the Tier 2 settings window. Unlike the bars (which
      # link libxkbcommon via SCTK), settings uses winit, which dlopens both
      # libwayland and libxkbcommon at runtime; Nix keeps neither in RPATH, so the
      # launcher provides them on LD_LIBRARY_PATH. SLINT_BACKEND=winit-software picks
      # slint's software renderer (as the bars use), so no GL stack is needed. Runs
      # as a transient user unit, inheriting WAYLAND_DISPLAY from the per-user
      # manager (set by thermos-session's import-environment).
      thermosSettings = pkgs.writeShellApplication {
        name = "thermos-settings";
        runtimeInputs = [ pkgs.systemd ];
        text = ''
          exec systemd-run --user --collect \
            --setenv=LD_LIBRARY_PATH=${pkgs.wayland}/lib:${pkgs.libxkbcommon}/lib \
            --setenv=FONTCONFIG_FILE=${fontsConf} \
            --setenv=SLINT_BACKEND=winit-software \
            ${apps}/bin/settings "$@"
        '';
      };

      # Start the desktop on the physical console once, when no graphical session
      # is already up. Serial/SSH logins fall through to a normal shell. base's
      # /etc/profile sources /etc/profile.d/*.sh for login shells.
      sessionHook = ''
        if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
          exec thermos-session
        fi
      '';

      # Each Tier 1 bar is an independent Wayland client run as a systemd USER
      # unit, supervised by the per-user instance. Restart=on-failure keeps a
      # crash local and self-healing: systemd respawns the dead bar alone, and
      # because the bars share no mutable state (each subscribes directly to its
      # authority: the compositor for the window list, logind/the daemon over
      # D-Bus), the survivors are untouched and the respawn rebuilds its view
      # from scratch.
      #
      # Wiring follows systemd.special(7) (systemd 260.1): a graphical-session
      # component declares PartOf=graphical-session.target so it stops with the
      # session, and ships a graphical-session.target.wants/ symlink (lowered
      # from Install.WantedBy by the units builder) since it is enabled
      # independently. thermos-session starts thermos-session.target, which binds
      barUnit = name: exec: {
        unitName = "${name}.service";
        scope = "user";
        unitConfig = {
          Unit = {
            Description = "ThermOS ${name}";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = exec;
            Restart = "on-failure";
            RestartSec = "1s";
            # The bars run slint's software renderer, but the workspace's
            # backend-winit (for the settings window) flips wayland-client to its
            # dlopen backend across the unified build. Nix omits dlopen'd libs from
            # RPATH, so the bar must find libwayland at runtime; the femtovg
            # renderer also inits fontconfig. Drop both when the bars build without
            # backend-winit (desktop/Cargo.toml).
            Environment = [
              "LD_LIBRARY_PATH=${pkgs.wayland}/lib"
              "FONTCONFIG_FILE=${fontsConf}"
            ];
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };

      # The compositor session target. graphical-session.target sets
      # RefuseManualStart=yes + StopWhenUnneeded=yes (systemd.special(7), 260.1):
      # it can only be pulled up as a dependency, and it stops once nothing needs
      # it. thermos-session starts THIS target, which binds graphical-session.target
      # up (pulling the bars via their .wants); stopping it on compositor exit makes
      # graphical-session.target unneeded, tearing it and the bars (PartOf) down.
      # Mirrors sway-session.target.
      sessionTarget = {
        unitName = "thermos-session.target";
        scope = "user";
        unitConfig = {
          Unit = {
            Description = "ThermOS graphical session";
            BindsTo = [ "graphical-session.target" ];
            Before = [ "graphical-session.target" ];
            Wants = [ "graphical-session-pre.target" ];
            After = [ "graphical-session-pre.target" ];
          };
        };
      };
    in
    if !options.enable then
      {
        packages = [ ];
        units = [ ];
        etc = [ ];
      }
    else
      {
        packages = [
          { package = apps; }
          { package = compositor; }
          { package = thermosSession; }
          { package = cosmicConfig; }
          { package = thermosSettings; }
        ];
        units = [
          sessionTarget
          (barUnit "thermos-dock" "${apps}/bin/dock")
          (barUnit "thermos-top" "${apps}/bin/top")
        ];
        etc = [
          {
            name = "profile.d/thermos-session.sh";
            text = sessionHook;
          }
        ];
      };
}
