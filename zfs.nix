# TODO: This will need to change, for different installations of NixOS.

{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "b36e475e";
  boot.zfs.devNodes = "/dev/disk/by-id";
  swapDevices = [
    { device = "/dev/disk/by-id/nvme-eui.88924e98b5be4a48bb0b501f0cfd5cc9-part4"; randomEncryption.enable = true; }
    { device = "/dev/disk/by-id/nvme-eui.d3e81d22e1499541aea81b4fa99b2d8c-part4"; randomEncryption.enable = true; }
  ];
  systemd.services.zfs-mount.enable = false;
  environment.etc."machine-id".source = "/state/etc/machine-id";
  environment.etc."zfs/zpool.cache".source
    = "/state/etc/zfs/zpool.cache";
  boot.loader = {
    generationsDir.copyKernels = true;
    ##for problematic UEFI firmware
    grub.efiInstallAsRemovable = true;
    efi.canTouchEfiVariables = false;
    ##if UEFI firmware can detect entries
    #efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot/efis/nvme-eui.88924e98b5be4a48bb0b501f0cfd5cc9-part1";
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
    grub.devices = [
      "/dev/disk/by-id/nvme-eui.88924e98b5be4a48bb0b501f0cfd5cc9"
      "/dev/disk/by-id/nvme-eui.d3e81d22e1499541aea81b4fa99b2d8c"
    ];
    grub.mirroredBoots = [
      { devices = [ "/dev/disk/by-id/nvme-eui.88924e98b5be4a48bb0b501f0cfd5cc9" ] ; efiSysMountPoint = "/boot/efis/nvme-eui.88924e98b5be4a48bb0b501f0cfd5cc9-part1"; path = "/boot"; }
      { devices = [ "/dev/disk/by-id/nvme-eui.d3e81d22e1499541aea81b4fa99b2d8c" ] ; efiSysMountPoint = "/boot/efis/nvme-eui.d3e81d22e1499541aea81b4fa99b2d8c-part1"; path = "/boot"; }
    ];
  };
}
