{ config, options, lib, ... }:

{
  options.my = let
    inherit (lib) mkOption;
    inherit (options.networking.firewall) allowedTCPPorts allowedUDPPorts;
  in {
    # Aspects that are what I intend but that might be changed implicitly by other modules due to
    # other indirect conditions.  By having these as option types, their values can be merged
    # and/or overridden (if ever needed) from other modules of mine.
    intended.netPorts = {
      # Which TCP ports I intend to allow to be open, based only on my configuration.
      TCP = mkOption {
        type = allowedTCPPorts.type;
        default = [];
        apply = allowedTCPPorts.apply;  # canonicalizePortList
      };
      # Which UDP ports I intend to allow to be open, based only on my configuration.
      UDP = mkOption {
        type = allowedUDPPorts.type;
        default = [];
        apply = allowedUDPPorts.apply;  # canonicalizePortList
      };
    };
  };

  config = let
    inherit (config.my.intended) netPorts;
  in {
    assertions = let
      inherit (config.networking.firewall) allowedTCPPorts allowedUDPPorts;
    in [{
      # Prevent unintended network ports from being opened.  Especially important since many of
      # the NixOS modules can open some others implicitly based on other conditions.
      assertion = (allowedTCPPorts == netPorts.TCP) && (allowedUDPPorts == netPorts.UDP);
      message = "Opened network ports are not what was intended.";
    }];

    networking = {
      firewall = {
        allowedTCPPorts = netPorts.TCP;
        allowedUDPPorts = netPorts.UDP;
      };
    };
  };
}
