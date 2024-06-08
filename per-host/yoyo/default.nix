# Options specific to this particular host machine.

{ config, pkgs, lib, is, ... }:

let
  inherit (builtins) elem pathExists;
  inherit (lib) mkIf;
  inherit (lib.lists) optional;
  inherit (lib.strings) optionalString;
in

{
  imports = [
    ./hardware-configuration.nix
  ]
  ++ (optional (pathExists ./private.nix) ./private.nix);

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

    # Not doing this anymore, because the latest kernel versions can cause problems due to being
    # newer than what the other packages in the stable NixOS channel expect.  E.g. it caused trying
    # to use a version of the VirtualBox extensions modules (or something) for the newer kernel but
    # this was marked broken which prevented building the NixOS system.
    #
    # # Use the latest kernel version that is compatible with the used ZFS
    # # version, instead of the default LTS one.
    # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    # # Following https://nixos.wiki/wiki/Linux_kernel --
    # # Note that if you deviate from the default kernel version, you should also
    # # take extra care that extra kernel modules must match the same version. The
    # # safest way to do this is to use config.boot.kernelPackages to select the
    # # correct module set:
    # extraModulePackages = with config.boot.kernelPackages; [ ];

    kernelParams = [
      "video=HDMI-A-1:3440x1440@100"  # Use 100 Hz, like xserver.
      "video=eDP-1:d"  # Disable internal lid screen.

      "tuxedo_keyboard.state=0"              # backlight off
      "tuxedo_keyboard.brightness=25"        # low, if turned on
      "tuxedo_keyboard.color_left=0xff0000"  # red, if turned on
    ];

    zfs.requestEncryptionCredentials = false;  # Or could be a list of selected datasets.

    # # To have classic ptrace permissions (instead of restricted, which is the new default).
    # # Setting this to 0 enables ptracing non-child processes, e.g. attaching GDB to an existing
    # # process, of a user's same UID.  The default value of 1 allows only child processes to be
    # # ptrace'd, e.g. GDB must start a process so it's a child.
    # kernel.sysctl."kernel.yama.ptrace_scope" = 0;
  };

  users.users = let
    common = config.my.users.commonAttrs;
  in {
    # v = common // {  # No longer using. It's all backed-up.
    #   extraGroups = [ "audio" ];
    # };
  };

  my.zfs.encryptedHomes = {
    noAuto = [
      "/home/v"
      "/home/v/old"
      { mountPoint = "/mnt/omit/home/v"; subDataset = "/home/v/omit"; }
    ];
  };

  # When booting into emergency or rescue targets, do not require the password
  # of the root user to start a root shell.  I am ok with the security
  # consequences, for this host.  Do not blindly copy this without
  # understanding.  Note that SYSTEMD_SULOGIN_FORCE is considered semi-unstable
  # as described in the file systemd-$VERSION/share/doc/systemd/ENVIRONMENT.md.
  systemd.services = {
    emergency.environment = {
      SYSTEMD_SULOGIN_FORCE = "1";
    };
    rescue.environment = {
      SYSTEMD_SULOGIN_FORCE = "1";
    };
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
      logRefusedConnections = true;
      logRefusedPackets = true;

      # Note that this is not needed when services.openssh.enable=true because that opens 22 itself.
      # allowedTCPPorts = [ 22 ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # This only reflects the DNS servers that are configured elsewhere (e.g. by DHCP).
  # This does not define the DNS servers.
  # Try to avoid using this, because it hard-codes assumption about where I'm at.
  # If it must be used occasionally, remember you can `nixos-rebuild test` for ephemeral changes.
  my.DNSservers = let
    home-router = "192.168.11.1";
  in
    mkIf false
      [ home-router ];

  # If in a situation where an upstream DNS server does not support DNSSEC
  # (i.e. cannot even proxy DNSSEC-format datagrams), this could be defined so
  # that DNS should still work.
  # services.resolved.dnssec = "allow-downgrade";  # Or "false".

  # services.openssh.enable = true;
  # my.intended.netPorts.TCP = [22];

  time.timeZone = "America/Los_Angeles";

  console.font = "ter-v24n";

  hardware.cpu.amd.updateMicrocode = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Controls for Tuxedo Computers hardware that also work on my Clevo NH55EJQ.
  hardware.tuxedo-keyboard.enable = true;  # Also enabled by the next below.
  # I use this for dynamic fan-speed adjusting based on CPU temperature.
  hardware.tuxedo-rs.enable = true;
  hardware.tuxedo-rs.tailor-gui.enable = is.GUI;

  # No longer needed since NixOS 24.05 has newer kernel version, and by default it uses the
  # amd_pstate_epp CPUFreq driver with that's built-in "powersave" governor, and that has similar
  # slower latency and highest frequency as the "conservative" governor, as desired.
  #
  # # Have dynamic CPU-frequency reduction based on load, to keep temperature and fan noise down
  # # when there's light load, but still allow high frequencies (limited by the separate choice of
  # # fan-speed-management-profile's curve's efficacy at removing heat) when there's heavy load.
  # # Other choices for this are: "schedutil" or "ondemand".  I choose "conservative" because it
  # # seems to not heat-up my CPUs as easily, e.g. when watching a video, which avoids turning-on
  # # the noisy fans, but it still allows the highest frequency when under sustained heavy load
  # # which is what I care about (i.e. I don't really care about the faster latency of "ondemand"
  # # nor the somewhat-faster latency of "schedutil").  Note: maximum performance is attained with
  # # the fans' speeds at the highest, which I have a different profile for in Tuxedo-rs's Tailor
  # # that I switch between as desired.
  # powerManagement.cpuFreqGovernor = "conservative";

  services.xserver = {
    exportConfiguration = true;

    xrandrHeads = [
      {
        # (The kernel names this same monitor HDMI-A-1.)
        output = "HDMI-1";
        primary = true;
        # This DisplaySize corresponds to my current external monitor which is a Philips 346B.
        # This value corresponds to what the device itself reports.
        # If this were not defined here, then `xdpyinfo` would have incorrect 96 DPI.
        monitorConfig = ''
          DisplaySize 797 334
        ''
        # This Modeline is not what the cvt nor gtf utilities give, because what
        # they give (which are a little different between the two) for 100 Hz
        # causes my monitor to fallback to 60 Hz for some reason.  This Modeline
        # is the same that my previous laptop used with this same monitor, and
        # 100 Hz works and the monitor does not switch modes when switching
        # users or switching virtual consoles (in conjunction with the video
        # argument in kernelParams above).
        + (optionalString (elem "video=HDMI-A-1:3440x1440@100" config.boot.kernelParams) ''
          Modeline "3440x1440@100.0"  543.50  3440 3488 3552 3600  1440 1443 1453 1510 -hsync +vsync
          Option "PreferredMode" "3440x1440@100.0"
        '');
      }
    ] ++ (optional (!(elem "video=eDP-1:d" config.boot.kernelParams)) {
      output = "eDP-1";
    });

    # This DPI corresponds to my current external monitor which is a Philips 346B.  Unset because
    # it's unneeded with the DisplaySize above and because it'd cause the driver to use a slightly
    # inconsistent value (794x332) for the display size.
    # dpi = 110;
  };

  services.printing.drivers = [ pkgs.hplip ];

  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplipWithPlugin ];
  };

  my.allowedUnfree = [ "hplip" ];

  # Have debug-info and source-code for packages where this is applied.  This is for packages that
  # normally don't provide these, and this uses my custom approach that overrides and overlays
  # packages to achieve having these.
  my.debugging.support = {
    all.enable = true;
    sourceCode.of.prebuilt.packages = with pkgs; [
      # TODO: Unsure if this is the proper way to achieve this for having the Rust library source
      # that corresponds to binaries built by Nixpkgs' `rustc`.
      # Have the Rust standard library source.  Get it from this `rustc` package, because it
      # locates it at the same `/build/rustc-$VER-src/` path where its debug-info has it recorded
      # for binaries it builds, and because this seems to be the properly corresponding source.
      # TODO: is this true, or else where is its sysroot or whatever?
      (rustc.unwrapped.overrideAttrs (origAttrs: {
        # Only keep the `library` source directory, not the giant `src` (etc.) ones.  This greatly
        # reduces the size that is output to the `/nix/store`.  The `myDebugSupport_saveSrcPhase`
        # of `myLib.pkgWithDebuggingSupport` will run after ours and will only copy the
        # `$sourceRoot` as it'll see it as changed by us here.  If debugging of `rustc` itself is
        # ever desired, this could be removed so that its sources are also included (I think).
        preBuildPhases = ["myDebugSupport_rust_onlyLibraryDir"];
        myDebugSupport_rust_onlyLibraryDir = ''
          export sourceRoot+=/library
          pushd "$NIX_BUILD_TOP/$sourceRoot"
        '';
      }))
    ];
  };

  nix = {
    daemonCPUSchedPolicy = "idle"; daemonIOSchedClass = "idle";  # So builds defer to my tasks.
    settings = {
      extra-experimental-features = "nix-command";
    };
  };

  # Enable Docker, run by non-root users.
  virtualisation.docker.rootless = {
    enable = true;
  };

  my.resolvedExtraListener =
    mkIf config.virtualisation.docker.rootless.enable
      # Choose an address that should be very unlikely to conflict with what
      # anything else needs to use.
      "192.168.255.53";
}
