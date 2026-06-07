{
  /**
    Shareable preamble includes some helper functions for vm tests

    Usage example:

    ```nix
    pkgs.testers.runNixOSTest {
      testScript = thermosLib.pythonPreamble + ''
        with thermos_vm("thermos", start_command) as thermos:
            # starts a ThermOS vm with automatic teardown
            # Since the VM is not registered through the test driver
            pass
      '';
    }
    ```
  */
  pythonPreamble = ''
    from contextlib import contextmanager

    @contextmanager
    def thermos_vm(name, start_command):
        vm = create_machine(start_command=start_command, name=name)
        try:
            vm.start()
            yield vm
        finally:
            vm.crash()
  '';
}
