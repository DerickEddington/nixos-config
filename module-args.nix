{ config, pkgs, lib, ... }:

{
  _module.args = {
    # Provide my own library of helpers.
    inherit (pkgs) myLib;  # Depends on my overlays adding it to `pkgs`.

    # Provide my own predicates for use across modules.
    is = let
      X = config.services.xserver;
      D = X.desktopManager;
    in rec {
      X11 = X.enable;
     #wayland = ;  # TODO: Not sure how nor how much NixOS supports.
      GUI = X11;  # TODO: Should include "or Wayland" also.
      GNOME = D.gnome.enable;
      KDE = D.plasma5.enable;
      MATE = D.mate.enable;
      XFCE = D.xfce.enable;
      # Could add others above, as needed, like: LXQt, etc.
      GTK = GNOME || MATE || XFCE;  # Maintenance: Extend as appropriate when others added above.
      desktop = GNOME || KDE || MATE || XFCE;  # Maintenance: Ditto.
    };
  };
}
