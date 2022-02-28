{ config, options, pkgs, lib, ... }:

let
  inherit (builtins) all elem hasAttr lessThan match sort readFile substring;
  inherit (lib) getName mkDefault mkOption types;
  inherit (lib.lists) flatten optionals unique;
  inherit (lib.attrsets) cartesianProductOfSets;
in

let
  # Choose for the particular host machine.
  hostName = "yoyo";
  # Network port numbers by service name.
  netPorts = rec {
    mDNS = [5353]; DNS_SD = mDNS; LLMNR = [5355];
  };
  # Aspects that are what I intend but might be changed implicitly by other
  # modules.
  intended = with config; with netPorts; rec {
    TCPports = flatten [
      # (Note: Do not need to open a TCP port for outgoing connections only.)
      (optionals my.publish.hostName LLMNR)
    ];
    UDPports = flatten [
      # (Note: Do need to open a UDP port for responses also.)
      (optionals (my.nameResolv.multicast || my.publish.hostName) (mDNS ++ LLMNR))
      (optionals my.publish.hostAspects DNS_SD)
      (optionals (services.avahi.enable && services.avahi.openFirewall) (mDNS ++ DNS_SD))
    ];
  };
  # Avahi and systemd-resolved coexistence.
  isAvahiMDNSresponder = with config.services;
    avahi.enable && avahi.publish.enable;
  doesAvahiPublishHostname = with config.services;
    isAvahiMDNSresponder && (avahi.publish.addresses || avahi.publish.domain);
  canResolvedBeMDNSresponder =
    ! isAvahiMDNSresponder;
in
{
  imports = [
    (./per-host + "/${hostName}")
    ./zfs.nix
  ];

  options.my = {
    hostName = mkOption { type = options.networking.hostName.type; };
    nameResolv = {
      multicast = mkOption {
        type = types.bool;
        default = true;
      };
    };
    publish = {
      hostAspects = mkOption {
        type = types.bool;
        default = false;  # Disabled for privacy.
      };
      hostName = mkOption {
        type = types.bool;
        default = config.my.publish.hostAspects;
      };
    };
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
        extraGroups = [ "wheel" "networkmanager" "wireshark" ];
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

      firewall = {
        allowedTCPPorts = intended.TCPports;
        allowedUDPPorts = intended.UDPports;
      };

      networkmanager = {
        enable = true;
        # Defaults that per-connection profiles use when there is no per-profile
        # value.  See `man NetworkManager.conf` and `man nm-settings-nmcli`.
        # These also cause NetworkManager to make the corresponding per-link
        # settings of systemd-resolved have the same values.
        connectionConfig = with config.my; let
          followResolvedOpts = config.services.resolved.enable;
          canBeMDNSresponder = (! isAvahiMDNSresponder)
                               && (followResolvedOpts -> canResolvedBeMDNSresponder);
          # Must use the numeric values instead of the documented string ones.
          default = -1; no = 0; resolve = 1; yes = 2;  # `yes` enables responder also.
          nonPublish =
            if nameResolv.multicast then resolve else no;
          multicastMode =
            if (publish.hostName && nameResolv.multicast) then yes else nonPublish;
        in {
          # Enable mDNS & LLMNR for all connection profiles by default.
          "connection.mdns" = if canBeMDNSresponder then multicastMode else nonPublish;
          "connection.llmnr" = multicastMode;  # (Avahi can't do LLMNR, so simpler.)
        };
        wifi = {
          backend = "iwd";
          powersave = true;
        };
      };

      wireless.iwd = {
        enable = true;  # More modern than wpa_supplicant.
        settings = {
          # # TODO: Needed/desired for using hidden SSIDs?
          # Settings.Hidden = true;
        };
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

      # Enable Avahi, for mDNS & DNS-SD, for local-network host & service
      # discovery.  It is ok for Avahi and systemd-resolved to both be running
      # with mDNS & DNS-SD enabled, because they can both use the same UDP port
      # at the same time.  I want both because only Avahi provides DNS-SD
      # publishing and only systemd-resolved provides LLMNR, and because some
      # apps might need/prefer one or the other.
      avahi = {
        enable = config.my.nameResolv.multicast;
        # Enable nsswitch to resolve hostnames (e.g. *.local) via mDNS via Avahi.
        nssmdns = true;
        # Whether to publish aspects of our own host so they can be discovered
        # by other hosts.
        publish = with config.my; rec {
          enable = publish.hostAspects || publish.hostName;
          # Enabling of sub-option(s) for publishing particular aspects:
          addresses =    publish.hostName;
          domain =       addresses;
          hinfo =        publish.hostAspects;
          userServices = publish.hostAspects;
          workstation =  publish.hostAspects;
        };
        # Which services to publish (I think) when publish.enable (I think).
        # extraServiceFiles = let
        #   premade = "${pkgs.avahi}/etc/avahi/services";
        # in {
        #   ssh = "${premade}/ssh.service";
        #   sftp-ssh = "${premade}/sftp-ssh.service";
        #   # ...
        # };
      };

      # Enable systemd-resolved.  Primarily to have its split DNS (which e.g. is
      # used by the "Use this connection only for resources on its network"
      # option of NetworkManager "connections") which is especially nice with
      # VPNs that provide their own private DNS.  Also nice are its caching,
      # activeness tracking, not suffixing search domains for multi-label names,
      # process separation for the network-protocol code, and dynamic
      # coordinated state.
      resolved = with config.my; let
        nonPublish =
          if nameResolv.multicast then "resolve" else "false";
        multicastMode =
          if (publish.hostName && nameResolv.multicast)
          then "true"  # "true" enables responder also.
          else nonPublish;
      in {
        enable = true;
        # See `man resolved.conf`.
        extraConfig =
          # services.resolved has an .llmnr attribute but not one for mDNS.  If
          # it has that added in the future, we try to detect that so we would
          # know to change to use that instead of having MulticastDNS= here in
          # extraConfig.
          assert all (a: !(hasAttr a config.services.resolved))
            ["mdns" "mDNS" "mDns" "MulticastDNS" "MulticastDns" "multicastDNS" "multicastDns"];
          ''
          # My services.resolved.extraConfig:
          # Note that these are only the global settings, and that some per-link
          # settings can override these.  NetworkManager has its own settings
          # system that it will use for determining the systemd-resolved
          # settings per-link, and so the
          # networking.networkmanager.connectionConfig options must also be
          # defined to achieve desired effects like consistently having
          # the same mDNS and LLMNR modes across global and per-link settings.

          # Empty to hopefully prevent using compiled-in fallback, for privacy.
          # I could not figure-out definitively whether this is unnecessary and
          # unused, when an /etc/resolv.conf or /etc/systemd/resolved.conf exist
          # even if they and all other relevant (e.g. dynamic per-link)
          # configurations do not specify any DNS servers at all.  The systemd
          # man pages are insufficiently clear - resolved.conf(5) suggests that
          # the compiled-in value is only used when this option is not given
          # (making me want to give it as empty), but systemd-resolved(8) also
          # suggests that the compiled-in value is used when simply no other DNS
          # servers are configured without saying anything about this option
          # (making me doubt whether there is any way to prevent using the
          # compiled-in value).  So might as well set it to empty and hope.  A
          # definitive workaround might be to override pkgs.systemd to rebuild
          # it with an empty compiled-in fallback (if its .nix derivation file
          # supported this), but I don't care that much and don't want
          # rebuilding to be done frequently when updating.  See also:
          # https://github.com/systemd/systemd/issues/494#issuecomment-118940330
          FallbackDNS=

          # Enable using mDNS for things that do not go through Avahi
          # (e.g. things that directly use /etc/resolv.conf and bypass the
          # Name Service Switch (NSS)), even with Avahi enabled (which can also
          # resolve mDNS).
          MulticastDNS=${if canResolvedBeMDNSresponder then multicastMode else nonPublish}

          # Might be desired in rare situations where the upstream classic
          # unicast DNS is e.g. a home router that provides some DNS but without
          # providing its own domain for searching, and where some single-label
          # name(s) are not resolvable via other "zero-config" (LLMNR)
          # responders.
          # ResolveUnicastSingleLabel=true
        '';

        # Enable Link-Local Multicast Name Resolution (LLMNR).
        llmnr = multicastMode;  # (Avahi can't do LLMNR, so simpler.)

        # Enable DNSSEC validation done locally.  Note that for private domains
        # (a.k.a. "site-private DNS zones") to not "conflict with DNSSEC
        # operation" (i.e. not have validation failures due to no-signature),
        # even when this option is set to "allow-downgrade", "negative trust
        # anchors" of systemd-resolved must also be defined for the private
        # domains to turn off DNSSEC validation.  There is a built-in
        # pre-defined set of these, including .home. and .test. which I use.
        # This default may be overridden in ./per-host/${hostName} when needed.
        dnssec = mkDefault "true";
      };

      # Enable CUPS to print documents.
      printing.enable = true;
    };

    # Some programs need SUID wrappers, can be configured further, or are
    # started in user sessions, and so should be done here and not in
    # environment.systemPackages.
    programs = {
      nm-applet.enable = true;

      ssh.askPassword = "${pkgs.ssh-askpass-fullscreen}/bin/ssh-askpass-fullscreen";

      # Install Wireshark with a group and setcap-wrapper setup for it.
      wireshark = {
        enable = true;
        package = if config.services.xserver.enable then pkgs.wireshark else pkgs.wireshark-cli;
      };

      # TODO
      # gnupg.agent = {
      #   enable = true;
      #   enableSSHSupport = true;
      # };
    };

    fonts = {
      # fontconfig.dpi = config.services.xserver.dpi;

      enableDefaultFonts = true;
      fonts = with pkgs; [
        ubuntu_font_family
      ];
    };

    # Make Qt theme like GTK.
    qt5 = let
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
        allowUnfreePredicate = pkg: elem (getName pkg) [
          "Oracle_VM_VirtualBox_Extension_Pack"
        ];
      };

      overlays = import ./nixpkgs/overlays.nix;
    };

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
        psmisc
        most
        wget
        htop
        git
        unzip
        gnupg
        ripgrep
        file
        screen
        aspell aspellDicts.en aspellDicts.en-computers aspellDicts.en-science
        cifs-utils
        sshfs
      ] ++ (if config.services.xserver.enable then (
        (optionals config.services.xserver.desktopManager.mate.enable [
          libreoffice
          rhythmbox
          transmission-gtk
          mate.mate-icon-theme-faenza
        ]) ++
        comixcursorsChosen
        ++ [
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
        # Prevent Git from using SSH_ASKPASS (which NixOS always sets).  This is
        # a workaround hack, relying on unspecified Git behavior, and hopefully
        # this is only temporary until a proper resolution.
        GIT_ASKPASS = "";
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

    # system.autoUpgrade.enable = true;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "21.05"; # Did you read the comment?

    assertions = let
      resolvedConf = config.environment.etc."systemd/resolved.conf".text;
      matchResolvedConfOption = conf: opt: val:
        (match "(^|.*\n)( *${opt} *= *${val} *)($|\n.*)" conf) != null;
    in
      (with config.services; with config.networking; [{
        # Prevent unintended network ports from being opened.  Especially
        # important since many of the NixOS modules can open some others
        # implicitly based on other conditions.
        assertion = with firewall; let
          canonical = ports: unique (sort lessThan (flatten ports));
          equal = a: b: (canonical a) == (canonical b);
        in
          (equal allowedTCPPorts intended.TCPports) && (equal allowedUDPPorts intended.UDPports);
        message =
          "Actually-opened network ports are not what was intended.";
      } {
        # Prevent having both systemd-resolved and Avahi as mDNS responders at
        # the same time, because, while it might work, there would be redundant
        # double responses sent out (I think).
        assertion =
          (resolved.enable && isAvahiMDNSresponder)
          -> (matchResolvedConfOption resolvedConf "MulticastDNS" "(resolve|0|no|false|off)");
        message =
          "Should not have both systemd-resolved and Avahi as mDNS responders.";
      } {
        # Prevent having NetworkManager configure per-connection mDNS
        # responding, when Avahi is also an mDNS responder.
        assertion =
          isAvahiMDNSresponder
          -> (networkmanager.enable
              -> ((networkmanager.connectionConfig ? "connection.mdns")
                  && (let no = 0; resolve = 1;
                          v = networkmanager.connectionConfig."connection.mdns";
                      in v == resolve || v == no)));
        message =
          "Should not have both NetworkManager per-connection and Avahi mDNS responding.";
      } {
        assertion = (resolved.fallbackDns != [])
                    -> !(matchResolvedConfOption resolved.extraConfig "FallbackDNS" "[^\n]*");
        message =
          "Cannot have both resolved.fallbackDns and FallbackDNS in resolved.extraConfig";
      }]);
  };
}
