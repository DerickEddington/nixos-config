{ config, options, pkgs, lib, myLib, ... }:

let
  inherit (builtins) attrNames elem listToAttrs readFile substring;
  inherit (lib) getName mkDefault mkIf mkOption types;
  inherit (lib.lists) optionals;
  inherit (lib.attrsets) cartesianProductOfSets filterAttrs;
in

let
  # Choose for the particular host machine.
  hostName = "yoyo";
in
{
  imports = [
    ./module-args.nix
    (./per-host + "/${hostName}")
    ./debugging.nix
    ./zfs
    ./networking
    ./secret-service.nix
    ./rootless-docker.nix
  ];

  options.my = {
    hostName = mkOption { type = options.networking.hostName.type; };
    users.commonAttrs = mkOption {
      type = with types; attrsOf anything;
      default = { isNormalUser = true; };
    };
    allowedUnfree = with types; mkOption { type = listOf str; };
  };

  config = {
    my.hostName = hostName;
    my.allowedUnfree = [
      "Oracle_VM_VirtualBox_Extension_Pack"
    ];
    my.secret-service.enable = true;  # Custom way of providing and using the Secret Service API.

    boot = {
      tmp = {
        cleanOnBoot = true;
        # useTmpfs = true;
      };
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

    # Users to have in all the hosts that use this configuration.
    #
    # Don't forget to set a password with `passwd` for each user, and possibly
    # setup a new ZFS dataset for their home, and then run, as the user,
    # `/etc/nixos/users/setup-home`.
    #
    # Per-host users should instead be defined in `per-host/$HOSTNAME/default.nix`.
    users.users = let
      common = config.my.users.commonAttrs;
    in {
      boss = common // {
        extraGroups = [ "wheel" "networkmanager" "wireshark" ];
      };
      d = common // {
        extraGroups = [ "audio" "scanner" "lp" ];
      };
      z = common;
      banking = common;
      bills = common // {
        extraGroups = [ "bills" ];
      };
    };

    users.groups = {
      bills = {};
    };

    # For each normal user, give it its own sub-directories under /mnt/omit/home/ and
    # /var/tmp/home/.  This is especially useful for a user to place large dispensable things that
    # it wants to be excluded from backups.
    systemd.tmpfiles.packages = let
      mkTmpfilesDirPkg = base:
        (myLib.tmpfiles.mkDirPkg'
          { ${base} = { user = "root"; group = "root"; mode = "0755"; }; }
          (listToAttrs (map (userName:
            { name = userName; value = { user = userName; group = "users"; mode = "0700"; }; })
            (attrNames (filterAttrs (n: v: v.isNormalUser) config.users.users))))
        ).pkg;
    in
      map mkTmpfilesDirPkg [
        "/mnt/omit/home"
        "/var/tmp/home"
      ];

    networking = {
      hostName = config.my.hostName;

      # Derive from our machine-id.  Use relative path so that this reads the
      # correct file when doing installs where the new system is located
      # somewhere other than / (e.g. /mnt/).
      hostId = substring 0 8 (readFile ../../etc/machine-id);

      firewall.allowPing = mkDefault false;

      networkmanager = {
        enable = true;
        wifi = {
          backend = "iwd";
          powersave = true;
        };
      };

      wireless.iwd = {
        enable = true;  # More modern than wpa_supplicant.
      };
    };

    security.pki.caCertificateBlacklist = [
    ];

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

      # Enable Avahi, for mDNS & DNS-SD, for local-network host & service
      # discovery.  It is ok for Avahi and systemd-resolved to both be running
      # with mDNS & DNS-SD enabled, because they can both use the same UDP port
      # at the same time.  I want both because only Avahi provides DNS-SD
      # publishing and only systemd-resolved provides LLMNR, and because some
      # apps might need/prefer one or the other.
      avahi = {
        enable = config.my.nameResolv.multicast;
      };

      # Enable systemd-resolved.  Primarily to have its split DNS (which e.g. is
      # used by the "Use this connection only for resources on its network"
      # option of NetworkManager "connections") which is especially nice with
      # VPNs that provide their own private DNS.  Also nice are its caching,
      # activeness tracking, not suffixing search domains for multi-label names,
      # process separation for the network-protocol code, and dynamic
      # coordinated state.
      resolved = {
        enable = true;
      };

      # Enable CUPS to print documents.
      printing.enable = true;
    };

    # Some programs need SUID wrappers, can be configured further, or are
    # started in user sessions, and so should be done here and not in
    # environment.systemPackages.
    programs = {
      nm-applet.enable = config.networking.networkmanager.enable;

      ssh = {
        # Have `ssh-agent` be already available for users which want to use it.  No harm in
        # starting it for users which don't use it (as long as their apps & tools are not
        # configured to accidentally use it unintentionally, but that's their choice).
        startAgent = true;
        # This is better than the other choices, because: it "grabs" the desktop (unlike GNOME's
        # Seahorse's which has some error when it tries to do that); and it doesn't depend on
        # other things (unlike KDE's ksshaskpass which depends on KWallet).
        askPassword = "${pkgs.ssh-askpass-fullscreen}/bin/ssh-askpass-fullscreen";
      };

      git = {
        enable = true;
        config = {
          safe.directory = ["/etc/nixos" "/etc/nixos/users/dotfiles"];
          transfer.credentialsInUrl = "die";
        };
      };

      # Install Wireshark with a group and setcap-wrapper setup for it.
      wireshark = {
        enable = true;
        package = if config.services.xserver.enable then pkgs.wireshark else pkgs.wireshark-cli;
      };

      gnupg.agent = {
        enable = true;
        enableExtraSocket = true;    # Why not? Upstream's default is this. Helps forwarding.
        enableBrowserSocket = true;  # Why not?
       #enableSSHSupport = true;  # Would only be for using GPG keys as SSH keys.
      };
    };

    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        ubuntu_font_family
      ];
    };

    # Make Qt theme like GTK.
    qt = let
      # This predicate exists so that it could be extended with others.
      isGtkBasedDesktopManager = config.services.xserver.desktopManager.mate.enable;
    in {
      enable = isGtkBasedDesktopManager;
      platformTheme = "gtk2";
      style = "gtk2";
    };

    nixpkgs = {
      config = {
        # Note that `NIXPKGS_ALLOW_UNFREE=1 nix-env -qa` can be used to see all
        # "unfree" packages without allowing permanently.

        # Allow and show all "unfree" packages that are available.
        # allowUnfree = true;

        # Allow and show only select "unfree" packages.
        allowUnfreePredicate = pkg: elem (getName pkg) config.my.allowedUnfree;
      };

      overlays = import ./nixpkgs/overlays.nix (_self: _super: {
                          debuggingSupportConfig = config.my.debugging.support;
                        });
    };

    environment = let
      # Reduced set of the Comix Cursors variants (don't want all of them).
      comixcursorsChosen =
        map ({color, hand}: pkgs.comixcursors."${hand}Opaque_${color}")
          (cartesianProductOfSets {
            color = [ "Blue" "Green" "Orange" "Red" ];
            hand = [ "" "LH_" ];
          });
    in {
      systemPackages =
      # Those arranged above
      [
      ]
      ++ (optionals config.services.xserver.enable
        comixcursorsChosen
      )
      # Those directly from `pkgs`
      ++ (with pkgs; [
        lsb-release
        man-pages
        man-pages-posix
        psmisc
        most
        wget
        htop
        lsof
      # git  # Installed via above programs.git.enable
        unzip
        gnupg
        ripgrep
        unstable.fd
        file
        screen
        aspell aspellDicts.en aspellDicts.en-computers aspellDicts.en-science
        cifs-utils
        sshfs
        bind.dnsutils
        pwgen
        socat
        xorg.lndir  # (Independent of Xorg being installed (I think).)
        hello  # Can be useful to test debugging.
      ]
      # If GUI desktop is enabled
      ++ (if config.services.xserver.enable then (
      (optionals config.services.xserver.desktopManager.mate.enable [
        libreoffice
        rhythmbox
        transmission-gtk
        mate.mate-icon-theme-faenza
        gnome.gucharmap gnome.gnome-characters
      ]) ++ [
        pop-icon-theme
        materia-theme
        material-icons
        material-design-icons
      ]) else [
        transmission
      ]));

      variables = rec {
        # Use absolute paths for these, in case some usage does not use PATH.
        VISUAL = "${pkgs.nano}/bin/nano";  # (Note: My users usually change this to Emacs.)
        EDITOR = VISUAL;
        PAGER = "${pkgs.most}/bin/most";
        # Prevent Git from using SSH_ASKPASS (which NixOS always sets).  This is
        # a workaround hack, relying on unspecified Git behavior, and hopefully
        # this is only temporary until a proper resolution.
        GIT_ASKPASS = "";
        # Where KeePassXC defaults to for its initial-location picking for new databases.
        KPXC_INITIAL_DIR = mkIf (elem pkgs.keepassxc config.environment.systemPackages)
                             "\${XDG_DATA_HOME:-$HOME/.local/share}/my";
      };
    };

    documentation.man.generateCaches = true;

    virtualisation.virtualbox = {
      host = {
        enable = true;
        enableExtensionPack = true;
      };
    };

    nix = {
      settings.auto-optimise-store = true;

      gc = {
        # Note: This can result in redownloads when store items were not
        # referenced anywhere and were removed on GC, but it is convenient.
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 90d";
      };
    };

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
