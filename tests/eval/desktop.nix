# Unit under test: /services/desktop impl (modules/services/desktop.nix). Asserts
# the bars are published as user-scoped, self-healing graphical-session units, a
# session target that binds graphical-session.target up, and that the module is
# inert when disabled.
{ tree, nixpkgs-lib, ... }:
let
  inherit (builtins)
    all
    any
    filter
    head
    match
    ;
  inherit (nixpkgs-lib) hasInfix;
in
{
  testDisabledEmpty = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { };
      in
      {
        inherit (impl) units packages;
      };
    expected = {
      units = [ ];
      packages = [ ];
    };
  };

  testPublishesBothBars = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
      in
      map (u: u.unitName) (filter (u: match ".*\\.service" u.unitName != null) impl.units);
    expected = [
      "thermos-dock.service"
      "thermos-top.service"
    ];
  };

  # graphical-session.target sets RefuseManualStart; thermos-session.target binds
  # it up as a dependency (and StopWhenUnneeded tears it down on session exit).
  testSessionTargetBindsGraphicalSession = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
        target = head (filter (u: u.unitName == "thermos-session.target") impl.units);
      in
      {
        scope = target.scope;
        bindsTo = target.unitConfig.Unit.BindsTo;
        before = target.unitConfig.Unit.Before;
      };
    expected = {
      scope = "user";
      bindsTo = [ "graphical-session.target" ];
      before = [ "graphical-session.target" ];
    };
  };

  testBarsAreUserScoped = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
      in
      all (u: u.scope == "user") impl.units;
    expected = true;
  };

  # The fault-isolation contract at the OS layer: a crashed bar is respawned by
  # the per-user instance (Restart=on-failure) and torn down with the session
  # (PartOf + Install.WantedBy graphical-session.target).
  testDockSupervision = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
        dock = head (filter (u: u.unitName == "thermos-dock.service") impl.units);
      in
      {
        restart = dock.unitConfig.Service.Restart;
        partOf = dock.unitConfig.Unit.PartOf;
        wantedBy = dock.unitConfig.Install.WantedBy;
      };
    expected = {
      restart = "on-failure";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };
  };

  testTopExecStartsBinary = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
        top = head (filter (u: u.unitName == "thermos-top.service") impl.units);
      in
      match ".*/bin/top" top.unitConfig.Service.ExecStart != null;
    expected = true;
  };

  testShipsCompositor = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
      in
      builtins.any (p: match "cosmic-comp.*" p.package.name != null) impl.packages;
    expected = true;
  };

  testShipsSessionLauncher = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
      in
      builtins.any (p: p.package.name == "thermos-session") impl.packages;
    expected = true;
  };

  # The Tier 2 settings window ships an on-demand launcher (thermos-settings)
  # that runs it as a transient user unit carrying the winit dlopen env. Without
  # it settings has no way to open in the desktop.
  testShipsSettingsLauncher = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
      in
      builtins.any (p: p.package.name == "thermos-settings") impl.packages;
    expected = true;
  };

  # The session is launched from the physical console only: the hook guards on
  # /dev/tty1 and execs the launcher. Serial/SSH logins fall through to a shell.
  testSessionHookExecsLauncherOnTty1 = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
        hook = head (filter (e: e.name == "profile.d/thermos-session.sh") impl.etc);
      in
      hasInfix "/dev/tty1" hook.text && hasInfix "exec thermos-session" hook.text;
    expected = true;
  };

  # The bars dlopen libwayland: the workspace's backend-winit forces wayland-client's
  # dlopen backend onto them, and Nix omits dlopen'd libs from RPATH, so the unit must
  # carry libwayland on LD_LIBRARY_PATH (else the bar exits NoWaylandLib) and a
  # fontconfig file for the femtovg init. Guards the wiring until the bars build
  # without backend-winit.
  testBarsCarryRuntimeLibs = {
    expr =
      let
        impl = tree.modules.services.modules.desktop { enable = true; };
        dock = head (filter (u: u.unitName == "thermos-dock.service") impl.units);
        env = dock.unitConfig.Service.Environment;
        anyMatch = pat: any (e: match pat e != null) env;
      in
      {
        wayland = anyMatch "LD_LIBRARY_PATH=.*wayland.*/lib";
        fontconfig = anyMatch "FONTCONFIG_FILE=.*";
      };
    expected = {
      wayland = true;
      fontconfig = true;
    };
  };
}
