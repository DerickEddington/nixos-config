# Options specific to this particular host machine.

{ config, pkgs, lib, ... }:

let
  inherit (builtins) elem;
  inherit (lib.lists) optional;
  inherit (lib.strings) optionalString;
in

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

  # TODO?: Maybe some options.my.xserver that fit my laptop's different GPUs and
  # display outputs and my monitor, which formalize how I want each combination
  # and which make it easy to switch, and which serve as a record of what I
  # figure out for them, and which control how the xserver config below is
  # constructed.

  # Define this again here to ensure it is checked that this is the same as what
  # /etc/nixos/configuration.nix also defined for the same option.
  my.hostName = "yoyo";

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
    pools = let id = "7km9ta"; in {
      boot.name = "boot-${id}";
      main.name = "main-${id}";
    };
    # TODO: Seems there's a bug with Linux 5.13+ that affects /dev/zvol symlinks
    #       https://github.com/openzfs/zfs/issues/12301
    #       https://github.com/openzfs/zfs/issues/12507
    #       https://github.com/fabianishere/pve-edge-kernel/issues/183
    usersZvolsForVMs = [
      { id = "1"; owner = "boss"; }
      { id = "2"; owner = "boss"; }
      { id = "3"; owner = "z"; }
      { id = "4"; owner = "z"; }
      # { id = "5"; owner = ; }
      # { id = "6"; owner = ; }
      # { id = "7"; owner = ; }
      # { id = "8"; owner = ; }
    ];
  };

  boot = {
    loader = {
      # If UEFI firmware can detect entries
      efi.canTouchEfiVariables = true;

      # # For problematic UEFI firmware
      # grub.efiInstallAsRemovable = true;
      # efi.canTouchEfiVariables = false;
    };

    # TODO: The ZFS zvol bug (mentioned above) is causing my zvols to not even
    #       appear, with the newer kernel version.  Once that is fixed and
    #       available in nixpkgs, re-enable using the newer kernel.
    # # Use the latest stable kernel, instead of the default LTS one.
    # kernelPackages = pkgs.linuxPackages_latest;
    # Following https://nixos.wiki/wiki/Linux_kernel --
    # Note that if you deviate from the default kernel version, you should also
    # take extra care that extra kernel modules must match the same version. The
    # safest way to do this is to use config.boot.kernelPackages to select the
    # correct module set:
    extraModulePackages = with config.boot.kernelPackages; [ ];

    kernelParams = [
      "video=HDMI-A-1:3440x1440@100"  # Use 100 Hz, like xserver.
      "video=eDP-1:d"  # Disable internal lid screen.

      "tuxedo_keyboard.state=0"              # backlight off
      "tuxedo_keyboard.brightness=25"        # low, if turned on
      "tuxedo_keyboard.color_left=0xff0000"  # red, if turned on
    ];
  };

  networking = {
    # # TODO: Might be needed to work with my router's MAC filter.  Though, the
    # # default of macAddress="preserve" might work once it has connected once
    # # (with the MAC filter disabled temporarily), and the default
    # # scanRandMacAddress=true might be ok since it sounds like it only affects
    # # scanning but not "preserve"d MAC address of previously-connected
    # # connections.
    # networkmanager = {
    #   wifi = {
    #     scanRandMacAddress = false;
    #     macAddress = "permanent";
    #   };
    # };

    firewall = {
      allowPing = false;

      # Note that this is not needed when services.openssh.enable=true because that opens 22 itself.
      # allowedTCPPorts = [ 22 ];
      # allowedUDPPorts = [ ... ];
    };

    # Enables wireless support via wpa_supplicant, instead of NetworkManager.
    # wireless.enable = true;
  };

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

  services.xserver = {
    exportConfiguration = true;

    xrandrHeads = [
      {
        # (The kernel names this same monitor HDMI-A-1 for some reason.)
        output = "HDMI-A-0";
        primary = true;
        # This Modeline is not what the cvt nor gtf utilities give, because what
        # they give (which are a little different between the two) for 100 Hz
        # causes my monitor to fallback to 60 Hz for some reason.  This Modeline
        # is the same that my previous laptop used with this same monitor, and
        # 100 Hz works and the monitor does not switch modes when switching
        # users or switching virtual consoles (in conjunction with the video
        # argument in kernelParams above).
        monitorConfig = optionalString (elem "video=HDMI-A-1:3440x1440@100" config.boot.kernelParams) ''
          Modeline "3440x1440@100.0"  543.50  3440 3488 3552 3600  1440 1443 1453 1510 -hsync +vsync
          Option "PreferredMode" "3440x1440@100.0"
        '';
      }
    ] ++ (optional (!(elem "video=eDP-1:d" config.boot.kernelParams)) {
      output = "eDP";
    });

    # Firefox doesn't honor, but MATE would.
    # dpi = 110;
  };
}
