# Aspects related to resolving and publishing host and service names.

{ config, pkgs, lib, ... }:

let
  inherit (builtins) all concatStringsSep elem hasAttr match;
  inherit (pkgs) writeShellScript;
  inherit (lib) mkDefault mkIf mkMerge optionals types;
  inherit (lib.attrsets) mapAttrs' mapAttrsToList;
  inherit (lib.lists) flatten;
  inherit (lib.strings) escapeShellArg escapeShellArgs optionalString;

  trustAnchorsFileNameValuePair = polarity:
    assert elem polarity ["positive" "negative"];
    (name: value: let
      mnemonicName = name;
      domainNames = value;
    in {
      name = "dnssec-trust-anchors.d/${mnemonicName}.${polarity}";
      value = { text = concatStringsSep "\n" domainNames; };
    });
  trustAnchorsFiles = polarity: trustAnchorsAttrs:
    mapAttrs' (trustAnchorsFileNameValuePair polarity) trustAnchorsAttrs;

  negativeTrustAnchorsNetworkManagerDispatcherScriptSpec = name: value: let
    connectionID = name;
    domainNames = value;
  in {
    type = "pre-up";
    source = writeShellScript "my-networkmanager-dispatcher-script--${connectionID}" ''
      readonly interface="$1"
      readonly action="$2"
      readonly domainNames=(${escapeShellArgs domainNames})

      function log {
        logger --tag nm-dispatch-script --priority daemon.info "$@"
      }

      case "$CONNECTION_ID" in
        (${escapeShellArg connectionID})
          case "$action" in
            (pre-up | vpn-pre-up)
              if resolvectl nta "$interface" "''${domainNames[@]}" ; then
                log "Set NTAs for $interface to:" "''${domainNames[@]}"
              else
                log "Failed to set NTAs for $interface"
              fi
            ;;
          esac
        ;;
      esac
    '';
  };
  negativeTrustAnchorsNetworkManagerDispatcherScripts = connectionProfileNTAsAttrs:
    mapAttrsToList
      negativeTrustAnchorsNetworkManagerDispatcherScriptSpec
      connectionProfileNTAsAttrs;
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
    resolvedExtraListener = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    DNSSEC = {
      trustAnchors = let
        commonDescription = {
          negative = {
            start = ''
              Custom negative trust anchors (NTAs) to partially disable DNSSEC validation.
              Each NTA is a domain name of a DNS subtree to disable validation for.'';
            end = ''
              It is often better to keep these as narrow as possible
              (e.g. "d.c.b.a.com" versus "a.com"), and so it's often better to have multiple
              versus one (e.g. "d.c.b.a.com" and "f.e.b.a.com" versus only "b.a.com").'';
          };
        };
      in {
        perLink = {
          negative = mkOption {
            description = ''
              ${commonDescription.negative.start}
              Each attribute's name is the name of a connection profile of NetworkManager,
              and its value is a list of NTAs that apply only to the corresponding network link
              (global is configured differently).
              ${commonDescription.negative.end}
            '';
            example = { "Job VPN" = ["funky.vpc.internal.acme.com"]; };
            type = types.attrsOf (types.listOf types.str);
            default = {};
          };
        };
        global = {
          negative = mkOption {
            description = ''
              ${commonDescription.negative.start}
              Each attribute creates its own /etc/dnssec-trust-anchors.d/$NAME.negative file
              containing the elements (NTAs) of its list value.
              These apply globally to all network links (per-link is configured differently).
              ${commonDescription.negative.end}
            '';
            example = { job-vpn = ["funky.vpc.internal.acme.com"]; };
            type = types.attrsOf (types.listOf types.str);
            default = {};
          };
          keepDefault = {
            negative = mkOption {
              description = ''
                NTAs to also add when my.DNSSEC.trustAnchors.global.negative is non-empty.
                This is needed because having one-or-more non-empty
                /etc/dnssec-trust-anchors.d/*.negative file(s) causes `resolved` to not use its
                built-in default set of NTAs, but usually you want to keep its default also.
                The default value of this option is the same as the built-in default of
                systemd as of v250.4.
                If the value is set to empty, then nothing is added.
              '';
              example = {};
              type = types.attrsOf (types.listOf types.str);
              default = {
                # Hopefully this almost never needs to be updated.
                # TODO: It'd be better to instead somehow generate this automatically from the
                # currently-used version of systemd.
                same-as-systemd-default = [
                  "home.arpa"
                  "10.in-addr.arpa"
                  "16.172.in-addr.arpa"
                  "17.172.in-addr.arpa"
                  "18.172.in-addr.arpa"
                  "19.172.in-addr.arpa"
                  "20.172.in-addr.arpa"
                  "21.172.in-addr.arpa"
                  "22.172.in-addr.arpa"
                  "23.172.in-addr.arpa"
                  "24.172.in-addr.arpa"
                  "25.172.in-addr.arpa"
                  "26.172.in-addr.arpa"
                  "27.172.in-addr.arpa"
                  "28.172.in-addr.arpa"
                  "29.172.in-addr.arpa"
                  "30.172.in-addr.arpa"
                  "31.172.in-addr.arpa"
                  "168.192.in-addr.arpa"
                  "d.f.ip6.arpa"
                  "corp"
                  "home"
                  "internal"
                  "intranet"
                  "lan"
                  "local"
                  "private"
                  "test"
                ];
              };
            };
          };
        };
      };
    };
  };

  config = let
    inherit (config.my) DNSservers nameResolv publish resolvedExtraListener DNSSEC;
    inherit (config.services) avahi resolved;
    inherit (config.networking) nameservers networkmanager;
    # Avahi and systemd-resolved coexistence.
    isAvahiMDNSresponder =
      avahi.enable && avahi.publish.enable;
    doesAvahiPublishHostname =
      isAvahiMDNSresponder && (avahi.publish.addresses || avahi.publish.domain);
    canResolvedBeMDNSresponder =
      ! isAvahiMDNSresponder;

    hasResolvedExtraListener = resolvedExtraListener != null && resolvedExtraListener != "";
    resolvedExtraListenerAddressSpec = {
      address = resolvedExtraListener;
      prefixLength = 32;  # Only the exact address.
    };

    hasCustomNTAs.global  = DNSSEC.trustAnchors.global.negative  != {};
    hasCustomNTAs.perLink = DNSSEC.trustAnchors.perLink.negative != {};

  in mkMerge [

  # Interrelated name-resolution
  {
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

        '' + (optionalString (resolvedExtraListener != null) ''
          # Make systemd-resolved listen on this additional address.
          # Especially useful for enabling Docker containers to use the host's
          # systemd-resolved (in conjunction with
          # `virtualisation.docker.rootless.dns`).
          DNSStubListenerExtra=${resolvedExtraListener}
        '');

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
  }

  # Extra systemd-resolved listener
  (mkIf hasResolvedExtraListener {
    # Assign an additional IP address (an alias), that is not in the reserved
    # loopback block (127.0.0.0/8), to the loopback device, so that our extra
    # listener of systemd-resolved at this address has an interface as needed,
    # and so that this interface is the loopback like usual.  This is especially
    # useful to enable containers (e.g. Docker) to route IP packets to the
    # host's loopback interface, which is especially useful to enable containers
    # to use the host's systemd-resolved for DNS.
    networking.interfaces.lo = {
      ipv4 = {
        addresses = [ resolvedExtraListenerAddressSpec ];
      };
    };

    # Hack to make our `resolvedExtraListener` have the "host" scope that a
    # loopback address should have.  Otherwise, it would have "global" scope but
    # that would be inconsistent with the other loopback addresses.  To instead
    # not have this hack, the solution would be for the NixOS
    # `networking.interfaces.<name>.ipv4.addresses` option-submodule to support
    # an additional `options` option where the `"scope"` could be given, like
    # `networking.interfaces.<name>.ipv4.routes.*.options` does.
    systemd.services.network-addresses-lo.postStart =
      assert elem resolvedExtraListenerAddressSpec
                  config.networking.interfaces.lo.ipv4.addresses;
      (let
        cidr = "${resolvedExtraListener}/${toString resolvedExtraListenerAddressSpec.prefixLength}";
      in ''
        echo -n 'changing scope of address ${cidr} to "host" scope ...'
        ip addr del "${cidr}" dev lo 2>&1
        ip addr add "${cidr}" scope host dev lo 2>&1
        echo "done"
      '');
  })

  # Custom global negative trust anchors
  (mkIf hasCustomNTAs.global (let
    NTAsFiles = trustAnchorsFiles "negative";
    inherit (DNSSEC.trustAnchors) global;
  in {
    assertions = [{
      assertion = hasCustomNTAs.global -> resolved.enable;
      message = "Custom global NTAs are only supported with systemd-resolved.";
    }];
    environment.etc = mkMerge [
      (NTAsFiles global.negative)
      # Another mkMerge element, to apply the option-merging logic for the possibility of
      # same-name attributes, so that same-name attributes have their value lists of trust-anchors
      # combined.
      (NTAsFiles global.keepDefault.negative)
    ];
  }))

  # Custom per-link negative trust anchors
  (mkIf hasCustomNTAs.perLink (let
    inherit (DNSSEC.trustAnchors) perLink;
  in {
    assertions = [{
      assertion = hasCustomNTAs.perLink -> (resolved.enable && networkmanager.enable);
      message = "Custom per-link NTAs are only supported with systemd-resolved and NetworkManager.";
    }];
    networking.networkmanager.dispatcherScripts =
      negativeTrustAnchorsNetworkManagerDispatcherScripts perLink.negative;
  }))

  ];
}
