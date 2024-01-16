# Use KeePassXC to provide the Secret Service API (which is over D-Bus).  It's better for that
# because: it can confirm and show notifications when an entry is accessed via that API; and
# entries integrate with its other features.  Also, configure some more things to use the Secret
# Service API.

{ config, pkgs, lib, ...}:

let
  inherit (lib) mkEnableOption mkIf mkForce;
in

{
  options.my.secret-service = {
    enable = mkEnableOption "my custom way of providing and using the Secret Service API";
  };

  config = let
    cfg = config.my.secret-service;
    inherit (config.services) xserver;
    isGUI = xserver.enable;
    isMATE = xserver.desktopManager.mate.enable;
    isKDE = xserver.desktopManager.plasma5.enable;
  in
    mkIf cfg.enable {
      assertions = [ {
        assertion = isMATE;
        message = "Only designed for use with MATE Desktop.";
      } {
        assertion = ! isKDE;
        message = "Don't know how to disable KDE's provider of the Secret Service.";
      } {
        assertion = isGUI;
        message = "Don't know how to only install `keepassxc-cli` without GUI dependencies.";
      }];

      # Don't start GNOME Keyring, because it's unneeded and would conflict (in the D-Bus), with
      # KeePassXC being the provider.
      services.gnome.gnome-keyring.enable = mkForce false;

      environment.systemPackages = let
        secret-tool = assert ! pkgs ? secret-tool;
                      pkgs.libsecret.out;  # As var, in case it's elsewhere in the future.
      in with pkgs; [
        # Install KeePassXC system-wide for all users.
        (if isGUI then
           keepassxc
         else
           keepassxc-cli  # Invalid: Too bad there's not this w/o needing GUI desktop.
        )
        # A CLI to the general Secret Service API.  Not necessary for things to use the API, but
        # is a useful CLI for doing scripted access and management of entries.
        secret-tool
      ];

      programs = {
        # A GUI to the general Secret Service API (and to SSH & GPG keys).  Not necessary for
        # things to use the API, but is a useful GUI for seeing what entries are offered by the
        # provider of it and for doing light management tasks of entries.
        seahorse.enable = isGUI;

        git = {
          package = pkgs.gitFull;  # Mostly to have `git-credential-libsecret`.
          config = {
            credential = {
              helper = "libsecret";  # My default. Users can override in their config.
              useHttpPath = true;  # Needed to differentiate repo URLs. Users could override.
            };
          };
        };
      };

      # Prevent using `gnome-keyring` for XDG Desktop Portal stuff.  This only has an effect if
      # `xdg.portal.enable` is true.  Unsure if or how well this would work-out, but we'd
      # certainly want this stuff to use KeePassXC instead.
      xdg.portal.config = {
        common = {
          default = [ "*" ];  # This means: Use the first portal implementation found.
          "org.freedesktop.impl.portal.Secret" = [ "keepassxc" ];  # TODO: What would impl this?
        };
      };
    };
}
