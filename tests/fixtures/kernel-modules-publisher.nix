/**
  Test publisher

  Publishes to: "/contracts/kernel-modules"
  Data: determined by options.data

  Injected in tests via 'configure { modules.tests.modules.<name> = ...; }'
*/
{ types, ... }:
{
  name = "kernel-modules-publisher";

  options.data = {
    type = types.any;
    default = [ ];
  };

  publish = [ "/contracts/kernel-modules" ];

  impl =
    { options, ... }:
    {
      "kernel-modules" = options.data;
    };
}
