{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "7b92cf39";
  boot.zfs.devNodes = "/dev/disk/by-id";
  systemd.services.zfs-mount.enable = false;
  environment.etc."machine-id".source = "/state/etc/machine-id";
  environment.etc."zfs/zpool.cache".source
    = "/state/etc/zfs/zpool.cache";
  boot.loader = {
    # If UEFI firmware can detect entries
    efi.canTouchEfiVariables = true;

    # # For problematic UEFI firmware
    # grub.efiInstallAsRemovable = true;
    # efi.canTouchEfiVariables = false;

    efi.efiSysMountPoint = "/boot/efis/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E-part2";

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
    grub.devices = [
      "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E"
      "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y"
    ];
    grub.mirroredBoots = [
      { devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E" ] ; efiSysMountPoint = "/boot/efis/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E-part2"; path = "/boot"; }
      { devices = [ "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y" ] ; efiSysMountPoint = "/boot/efis/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y-part2"; path = "/boot"; }
    ];
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
