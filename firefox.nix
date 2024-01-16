self: super:

let
  inherit (super) firefox;
  inherit (self) keepassxc /*fetchFirefoxAddon*/;
in
  firefox.override {

    # See https://github.com/mozilla/policy-templates or
    # about:policies#documentation for more possibilities.
    extraPolicies = {
      CaptivePortal = false;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFirefoxAccounts = true;
      FirefoxHome = {
        Search = false;
        TopSites = false;
        Highlights = false;
        Pocket = false;
        Snippets = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        SkipOnboarding = true;
      };
    };

    extraPrefs = ''
    '';

    # Note: NixOS 21.11 rejects if this attribute is even defined, when the
    # Firefox is not ESR.
    # Note: If this were non-empty, then manually-installed addons would be
    # disabled, which I think means that addons installed via users'
    # home-manager (e.g. via NUR) would be disabled, which means that addons
    # would not be upgraded to their latest versions because specifying them
    # here requires pinning them to a version unlike with home-manager+NUR where
    # the versions are upgraded.
    # nixExtensions = [
    #   # (fetchFirefoxAddon {
    #   #   name = ""; # Has to be unique!
    #   #   url = "https://addons.mozilla.org/firefox/downloads/.xpi";
    #   #   sha256 = "";
    #   # })
    # ];

    nativeMessagingHosts = [
      keepassxc  # Allow the KeePassXC-Browser extension to communicate, when a user installed it.
    ];
  }
