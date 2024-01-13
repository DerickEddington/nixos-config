# Sub-modules that organize the more-involved details of my networking configuration.

{ config, lib, ... }:

let
  inherit (lib) mkIf;
in
{
  imports = [
    ./firewall.nix
    ./names.nix
  ];

  systemd.user.services.nm-applet = mkIf config.programs.nm-applet.enable {
    serviceConfig.Restart = "on-failure";
  };
}
