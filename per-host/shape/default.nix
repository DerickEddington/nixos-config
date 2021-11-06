# Options specific to this particular host machine.

{ config, pkgs, ... }:

with builtins;

{
  imports = [
    ./hardware-configuration.nix

    # TODO: Until tuxedo-control-center is in pkgs, must fetch directly from the
    #       contributor.  Once it is in pkgs, this variable and its uses should
    #       be deleted, and the hardware.tuxedo-control-center.enable option
    #       (defined below) will already be declared.
    (let
       ext-tcc = assert ! (let nixpkgs = import <nixpkgs> {}; in nixpkgs ? tuxedo-control-center);
                 import (fetchTarball https://github.com/blitz/tuxedo-nixos/archive/master.tar.gz);
     in
       ext-tcc.module)
  ];

  # Define this again here to ensure it is checked that this is the same as what
  # /etc/nixos/configuration.nix also defined for the same option.
  my.hostName = "shape";

  my.zfs = {
    mirrorDrives = [  # Names under /dev/disk/by-id/
      "nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E"
      "nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y"
    ];
    partitions = {
      legacyBIOS = 1;
      EFI        = 2;
      boot       = 3;
      main       = 4;
      swap       = 5;
    };
    pools = let id = "1z9h4t"; in {
      boot.name = "boot-${id}";
      main.name = "main-${id}";
    };
  };

  boot = {
    loader = {
      # If UEFI firmware can detect entries
      efi.canTouchEfiVariables = true;

      # # For problematic UEFI firmware
      # grub.efiInstallAsRemovable = true;
      # efi.canTouchEfiVariables = false;
    };

    # Use the latest stable kernel, instead of the default LTS one.
    kernelPackages = pkgs.linuxPackages_latest;
    # Following https://nixos.wiki/wiki/Linux_kernel --
    # Note that if you deviate from the default kernel version, you should also
    # take extra care that extra kernel modules must match the same version. The
    # safest way to do this is to use config.boot.kernelPackages to select the
    # correct module set:
    extraModulePackages = with config.boot.kernelPackages; [ ];

    kernelParams = [
      "tuxedo_keyboard.state=0"              # backlight off
      "tuxedo_keyboard.brightness=25"        # low, if turned on
      "tuxedo_keyboard.color_left=0xff0000"  # red, if turned on
    ];
  };

  networking.hostId = "7b92cf39";

  time.timeZone = "America/Los_Angeles";

  console.font = "ter-v24n";

  hardware.cpu.amd.updateMicrocode = true;

  # hardware.video.hidpi.enable = true;  # TODO? Maybe try with 21.11. Was broken with 21.05

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Drivers from Tuxedo Computers that also work on my Clevo NH55EJQ.
  hardware.tuxedo-keyboard.enable = true;  # Also enabled by the next below.
  hardware.tuxedo-control-center.enable = true;
}
