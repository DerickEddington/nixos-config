# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, options, pkgs, lib, ... }:

let
  # Choose for the particular host machine.
  hostName = "shape";
in
{
  imports = [
    (./per-host + "/${hostName}")
    ./zfs.nix
  ];

  options.my = {
    hostName = lib.mkOption { type = options.networking.hostName.type; };
  };

  config = {
    my.hostName = hostName;

    boot = {
      cleanTmpDir = true;
      # tmpOnTmpfs = true;
    };

    i18n.defaultLocale = "en_US.UTF-8";

    console = {
      # earlySetup = true;
      packages = with pkgs; [
        terminus_font
      ];
      useXkbConfig = true;
      # keyMap = "us";
    };

    # Don't forget to set a password with `passwd` for each user, and possibly
    # setup a new ZFS dataset for their home, and then run, as the user,
    # `/etc/nixos/users/setup-home`.
    users.users = let
      common = {
        isNormalUser = true;
      };
    in {
      boss = common // {
        extraGroups = [ "wheel" "networkmanager" ];
      };
      d = common;
      z = common;
    };

    networking = {
      hostName = config.my.hostName;

      # wireless.enable = true;  # Enables wireless support via wpa_supplicant.

      networkmanager = {
        enable = true;
        wifi.powersave = true;
      };

      # The global useDHCP flag is deprecated, therefore explicitly set to false here.
      # Per-interface useDHCP will be mandatory in the future, so this generated config
      # replicates the default behaviour.
      # useDHCP = false;
      # interfaces.enp0s3.useDHCP = true;

      # Configure network proxy if necessary
      # proxy.default = "http://user:password@proxy:port/";
      # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

      firewall = {
        # Open ports in the firewall.
        # allowedTCPPorts = [ 22 ];
        # allowedUDPPorts = [ ... ];
        # Or disable the firewall altogether.
        # enable = false;
      };
    };

    services = {
      # openssh.enable = true;

      # Enable the X11 windowing system.
      xserver = {
        enable = true;
        autorun = true;

        # Configure keymap in X11
        layout = "us";
        xkbOptions = "ctrl:nocaps";

        # Enable touchpad support (enabled default in most desktopManager).
        libinput.enable = true;
        libinput.touchpad.tapping = false;

        # Firefox doesn't honor, but MATE would.
        # dpi = 110;

        desktopManager.mate.enable = true;
      };

      # Enable CUPS to print documents.
      printing.enable = true;
    };

    programs = {
      nm-applet.enable = true;

      # TODO: Not sure
      # gnupg.agent = {
      #   enable = true;
      #   enableSSHSupport = true;
      # };

      # Some programs need SUID wrappers, can be configured further or are
      # started in user sessions.
      # mtr.enable = true;
    };

    fonts = {
      # fontconfig.dpi = config.services.xserver.dpi;

      enableDefaultFonts = true;
      fonts = with pkgs; [
        ubuntu_font_family
      ];
    };

    nixpkgs.config = {
      # Note that `NIXPKGS_ALLOW_UNFREE=1 nix-env -qa` can be used to see all
      # "unfree" packages without allowing permanently.

      # Allow and show all "unfree" packages that are available.
      # allowUnfree = true;

      # Allow and show only select "unfree" packages.
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        # "${name}"
      ];
    };

    environment = let
      with-unhidden-gitdir = import ./users/with-unhidden-gitdir.nix { inherit pkgs; };
      myEmacs = import ./emacs.nix { inherit pkgs; };
      myFirefox = import ./firefox.nix { inherit pkgs; };
    in {
      systemPackages = [
        with-unhidden-gitdir
        myEmacs
        myFirefox
      ]
      ++ (with pkgs; [
        lsb-release
        man-pages
        man-pages-posix
        most
        wget
        htop
        git
        unzip
        gnupg
        ripgrep
        file
        screen
      ]) ++ (if config.services.xserver.enable then (with pkgs; [
        # TODO: Only have the ones that I keep using.
        bibata-cursors
        bibata-extra-cursors
        capitaine-cursors
        numix-cursor-theme
        openzone-cursors
        xorg.xcursorthemes
        pop-icon-theme
        materia-theme
        material-icons
        material-design-icons
      ]) ++ (if config.services.xserver.desktopManager.mate.enable then (with pkgs; [
        mate.mate-icon-theme-faenza
        libreoffice
        rhythmbox
      ]) else []) else []);

      variables = rec {
        # Use absolute paths for these, in case some usage does not use PATH.
        VISUAL = "${myEmacs}/bin/emacs --no-window-system";
        EDITOR = VISUAL;
        PAGER = "${pkgs.most}/bin/most";
      };
    };

    nix = {
      autoOptimiseStore = true;

      gc = {
        # Note: This can result in redownloads when store items were not
        # referenced anywhere and were removed on GC, but it is convenient.
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 90d";
      };
    };

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "21.05"; # Did you read the comment?
  };
}
