# Aspects related to resolving and publishing host and service names.

{ config, lib, ... }:

let
  inherit (builtins) all hasAttr match;
  inherit (lib) mkDefault optionals types;
  inherit (lib.lists) flatten;
in

{
  options.my = let
    inherit (lib) mkOption;
  in {
    DNSservers = mkOption {
      description = ''
        Ancillary list of the host's current DNS servers.
        Should be set to reflect what they were elsewhere configured to be.
        Does not define what DNS servers are used by the host.
        Only used by my config where a concrete value must be given.
      '';
      type = types.listOf types.str;
      default = config.networking.nameservers;
    };
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

  config = let
    inherit (config.my) DNSservers nameResolv publish;
    inherit (config.services) avahi resolved;
    inherit (config.networking) nameservers networkmanager;
    # Avahi and systemd-resolved coexistence.
    isAvahiMDNSresponder =
      avahi.enable && avahi.publish.enable;
    doesAvahiPublishHostname =
      isAvahiMDNSresponder && (avahi.publish.addresses || avahi.publish.domain);
    canResolvedBeMDNSresponder =
      ! isAvahiMDNSresponder;
  in {
    assertions = let
      resolvedConf =
        config.environment.etc."systemd/resolved.conf".text;
      matchResolvedConfOption = conf: opt: val:
        (match "(^|.*\n)( *${opt} *= *${val} *)($|\n.*)" conf) != null;
    in [{
      assertion = nameservers != [] -> DNSservers == nameservers;
      message = "Ancillary list of DNS servers does not reflect the manually-defined list.";
    } {
      # Prevent having both systemd-resolved and Avahi as mDNS responders at the same time,
      # because, while it might work, there would be redundant double responses sent out (I
      # think).
      assertion =
        (resolved.enable && isAvahiMDNSresponder)
        -> (matchResolvedConfOption resolvedConf "MulticastDNS" "(resolve|0|no|false|off)");
      message =
        "Should not have both systemd-resolved and Avahi as mDNS responders.";
    } {
      # Prevent having NetworkManager configure per-connection mDNS responding, when Avahi is also
      # an mDNS responder.
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
      # Prevent repeat forms in `resolved` config file.
      assertion = (resolved.fallbackDns != [])
                  -> !(matchResolvedConfOption resolved.extraConfig "FallbackDNS" "[^\n]*");
      message =
        "Cannot have both resolved.fallbackDns and FallbackDNS in resolved.extraConfig";
    }];

    my = {
      intended.netPorts = let
        mDNS = [5353]; DNS_SD = mDNS; LLMNR = [5355];
      in {
        TCP = flatten [
          # (Note: Do not need to open a TCP port for outgoing connections only.)
          (optionals publish.hostName LLMNR)
        ];
        UDP = flatten [
          # (Note: Do need to open a UDP port for responses also.)
          (optionals (nameResolv.multicast || publish.hostName) (mDNS ++ LLMNR))
          (optionals publish.hostAspects DNS_SD)
          (optionals (avahi.enable && avahi.openFirewall) (mDNS ++ DNS_SD))
        ];
      };
    };

    networking = {
      networkmanager = {
        # Defaults that per-connection profiles use when there is no per-profile value.  See `man
        # NetworkManager.conf` and `man nm-settings-nmcli`.  These also cause NetworkManager to
        # make the corresponding per-link settings of systemd-resolved have the same values.
        connectionConfig = let
          followResolvedOpts = resolved.enable;
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
      };

      wireless.iwd = {
        settings = {
          # # TODO: Needed/desired for using hidden SSIDs?
          # Settings.Hidden = true;
        };
      };
    };

    services = {
      avahi = {
        # Enable nsswitch to resolve hostnames (e.g. *.local) via mDNS via Avahi.
        nssmdns = true;
        # Whether to publish aspects of our own host so they can be discovered by other hosts.
        publish = rec {
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

      resolved = let
        nonPublish =
          if nameResolv.multicast then "resolve" else "false";
        multicastMode =
          if (publish.hostName && nameResolv.multicast)
          then "true"  # "true" enables responder also.
          else nonPublish;
      in {
        # See `man resolved.conf`.
        extraConfig =
          # services.resolved has an .llmnr attribute but not one for mDNS.  If it has that added
          # in the future, we try to detect that so we would know to change to use that instead of
          # having MulticastDNS= here in extraConfig.
          assert all (a: !(hasAttr a resolved))
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

          # Empty to prevent using compiled-in fallback servers (which are
          # Googstapo & Cloudfart), for privacy and because if my situation
          # fails to provide DNS then I want that to be apparent.  I tested
          # (with a link setup without DNS) that fallbacks are not used when
          # this is set to empty, but are if it is not set.  The systemd man
          # pages and internet search results are somewhat unclear about when
          # exactly the fallbacks are used or not.  So even after testing, I'm
          # only 99% sure that "empty to prevent" can be depended on into the
          # future.
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
        # (a.k.a. "site-private DNS zones") to not "conflict with DNSSEC operation" (i.e. not have
        # validation failures due to no-signature), even when this option is set to
        # "allow-downgrade", "negative trust anchors" of systemd-resolved must also be defined for
        # the private domains to turn off DNSSEC validation.  There is a built-in pre-defined set
        # of these, including .home. and .test. which I use.  This default may be overridden in
        # ./per-host/${hostName} when needed.
        dnssec = mkDefault "true";
      };
    };
  };
}
