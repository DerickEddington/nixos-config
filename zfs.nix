# Created by me, following:
# https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS/0-overview.html

{ config, pkgs, ... }:

with builtins;

let
  hostName = config.networking.hostName;
  perHost = config._module.args.mine.perHost.${hostName};
  inherit (perHost) firstDrive mirrorDrives partitions;
in
{ boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";
  systemd.services.zfs-mount.enable = false;
  environment.etc."machine-id".source = "/state/etc/machine-id";
  environment.etc."zfs/zpool.cache".source
    = "/state/etc/zfs/zpool.cache";
  boot.loader = {
    efi.efiSysMountPoint = "/boot/efis/${firstDrive}-part${toString partitions.EFI}";

    generationsDir.copyKernels = true;

    grub.enable = true;
    grub.version = 2;
    grub.copyKernels = true;
    grub.efiSupport = true;
    grub.zfsSupport = true;
    # for systemd-autofs
    grub.extraPrepareConfig = ''
      mkdir -p /boot/efis
      for i in  /boot/efis/*; do mount $i ; done
    '';
    grub.devices = map (drive: "/dev/disk/by-id/${drive}") mirrorDrives;
    grub.mirroredBoots =
      map (drive: { devices = [ "/dev/disk/by-id/${drive}" ];
                    efiSysMountPoint = "/boot/efis/${drive}-part${toString partitions.EFI}";
                    path = "/boot"; })
        mirrorDrives;
  };

  # ZFS does not support hibernation and so it must not be done.  (But suspend
  # is safe and allowed.)
  # https://nixos.wiki/wiki/ZFS
  # https://github.com/openzfs/zfs/issues/260
  boot.kernelParams = [ "nohibernate" ];

  services.zfs = {
    trim.enable = true;
    autoScrub.enable = true;
  };
}
