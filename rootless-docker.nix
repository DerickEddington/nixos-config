{ config, pkgs, lib, ... }:

let
  inherit (lib) mkForce mkIf optionals;

  cfg = config.virtualisation.docker;
in
{
  environment.systemPackages =
    # If root-less Docker is enabled and using FUSE OverlayFS then we want to have its
    # command-line tool.
    (with cfg.rootless;
      (optionals (    enable
                   && (    !(daemon.settings ? storage-driver)
                        || daemon.settings.storage-driver == "fuse-overlayfs"))
        pkgs.fuse-overlayfs)) ;

  # Docker run by non-root users.  When enabled, each user runs their own daemon that stores under
  # the user's home.  Not enabled here (default is disabled).
  virtualisation.docker.rootless = {
    setSocketVariable = true;
    daemon.settings = {
      # Works on top of any FS, but is inefficient.
     #storage-driver = "vfs";

      # As of 2022-07-27 with NixOS 22.05.1988, fuse-overlayfs is broken,
      # seemingly due to fusermount being one of the special setuid-wrappers
      # that NixOS has and this wrapper program has assertions and one of them
      # (unknown which) fails for some unknown reason and causes the program
      # to abort and crash, which breaks its use with Docker.
     #storage-driver = "fuse-overlayfs";

      # This works on top of ZFS only for OpenZFS versions 2.2+.
      # (For older versions, the workaround is to:
      # make a zvol (e.g. as a sub dataset of an encrypted home
      # dataset, so it's also encrypted) and make an ext4 FS on that zvol,
      # since overlay2 is supported on top of ext4, and mount that on
      # ~/.local/share/docker/).
      storage-driver = "overlay2";

      dns = let
        inherit (config.my) resolvedExtraListener;
      in
        mkIf (resolvedExtraListener != null && resolvedExtraListener != "")
          [ resolvedExtraListener ];
    };
  };

  # Might be needed if fuse-overlayfs were used above, but not sure.
  # programs.fuse.userAllowOther =
  #   cfg.rootless.daemon.settings.storage-driver == "fuse-overlayfs";

  # This is the Unit for `virtualisation.docker.rootless` above.
  systemd.user.services.docker = {
    # By default, do not auto-start it for all users.  A user can auto-start it via their Home
    # Manager configuration by: `my.rootlessDocker.autoStart = true` (see
    # ./users/dotfiles/.config/home-manager/common/rootless-docker.nix)
    wantedBy = mkForce [];
  };
}
