# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, options, pkgs, lib, ... }:

let
  inherit (builtins) elem readFile substring;
  inherit (lib) getName mkOption optionals;
  inherit (lib.attrsets) cartesianProductOfSets;
in

let
  # Choose for the particular host machine.
  hostName = "yoyo";
in
{
  imports = [
    (./per-host + "/${hostName}")
    ./zfs.nix
  ];

  options.my = {
    hostName = mkOption { type = options.networking.hostName.type; };
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
      d = common // {
        extraGroups = [ "audio" ];
      };
      z = common;
      banking = common;
      bills = common;
    };

    networking = {
      hostName = config.my.hostName;

      # Derive from our machine-id.  Use relative path so that this reads the
      # correct file when doing installs where the new system is located
      # somewhere other than / (e.g. /mnt/).
      hostId = substring 0 8 (readFile ../../state/etc/machine-id);

      networkmanager = {
        enable = true;
        wifi.powersave = true;
      };
    };

    services = {
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

        desktopManager.mate.enable = true;

        displayManager.lightdm = {
          # background = pkgs.nixos-artwork.wallpapers.simple-red.gnomeFilePath;
          greeters.gtk = {
            theme.name = "Adwaita-dark";
            cursorTheme = {
              package = pkgs.comixcursors.LH_Opaque_Orange;
              name = "ComixCursors-LH-Opaque-Orange";
              size = 48;
            };
          };
        };
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
      allowUnfreePredicate = pkg: elem (getName pkg) [
        "Oracle_VM_VirtualBox_Extension_Pack"
      ];
    };

    nixpkgs.overlays = [
      (self: super: {
        # TODO: Until comixcursors is in nixpkgs, must use my external package.
        #       Once it is in nixpkgs, this should be deleted.
        comixcursors = assert ! (super ? comixcursors);
                       super.callPackage (fetchGit {
                         url = https://github.com/DerickEddington/nix-comixcursors.git;
                         ref = "main";
                       }) {};
      })
    ];

    environment = let
      with-unhidden-gitdir = import ./users/with-unhidden-gitdir.nix { inherit pkgs; };
      myEmacs = import ./emacs.nix { inherit pkgs; };
      myFirefox = import ./firefox.nix { inherit pkgs; };
      # Reduced set of the Comix Cursors variants (don't want all of them).
      comixcursorsChosen =
        map ({color, hand}: pkgs.comixcursors."${hand}Opaque_${color}")
          (cartesianProductOfSets {
            color = [ "Blue" "Green" "Orange" "Red" ];
            hand = [ "" "LH_" ];
          });
    in {
      systemPackages = (with pkgs; [
        with-unhidden-gitdir
        myEmacs
        myFirefox
      ] ++ [
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
      ] ++ (if config.services.xserver.enable then (
        (optionals config.services.xserver.desktopManager.mate.enable [
          libreoffice
          rhythmbox
          transmission-gtk
          mate.mate-icon-theme-faenza
        ]) ++
        comixcursorsChosen
        ++ [
          # TODO: Only have the ones that I keep using.
          pop-icon-theme
          materia-theme
          material-icons
          material-design-icons
        ]) else [
          transmission
        ]));

      variables = rec {
        # Use absolute paths for these, in case some usage does not use PATH.
        VISUAL = "${myEmacs}/bin/emacs --no-window-system";
        EDITOR = VISUAL;
        PAGER = "${pkgs.most}/bin/most";
      };
    };

    virtualisation.virtualbox = {
      host = {
        enable = true;
        enableExtensionPack = true;
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

    # TODO: Enable this once my /etc/nixos/configuration.nix stays constant.
    # system.autoUpgrade.enable = true;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "21.05"; # Did you read the comment?
  };
}
