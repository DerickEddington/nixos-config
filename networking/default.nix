# Sub-modules that organize the more-involved details of my networking configuration.

{ ... }:

{
  imports = [
    ./firewall.nix
    ./names.nix
  ];
}
