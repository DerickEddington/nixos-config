# This file, being separate, enables using the same overlays for the NixOS system configuration
# (which affects operations like `nixos-rebuild`) and for the users' configurations (which affects
# operations like `nix-env` and `home-manager`) that also import this file.

deps:  # `deps` is a function that returns dependencies for here, given a `self` and `super` pair.

let
  inherit (builtins) compareVersions elem match replaceStrings;
  isStableVersion =
    pkgs: isNull (match "pre.*" pkgs.lib.trivial.versionSuffix);
in

[
  # Make the nixos-unstable channel available as pkgs.unstable, for stable
  # versions of pkgs only.
  (self: super:
    if isStableVersion super then
      {
        unstable = assert ! (super ? unstable);
          # Pass the same config so that attributes like allowUnfreePredicate
          # are propagated.
          import <nixos-unstable> { inherit (self) config; };
      }
    else {})

  # Provide my own library of helpers.
  (self: super:
    assert ! (super ? myLib);
    {
      myLib = import ../lib { pkgs = self; };
    })

  # Firefox with my extra configuration.  My users usually install this via Home Manager.
  (self: super:
    { firefox = import ../firefox.nix self super; })

  # Tuxedo-rs newer version than in stable channel.  Don't use unstable channel, so this is built
  # with stable's Rust env and stdEnv, and so the version only changes when I want.
  (let ver = "0.2.4";  # TODO: Periodically check if a newer version is released in the future.
   in (self: super: {
     tuxedo-rs =
       assert (compareVersions super.tuxedo-rs.version ver) == -1;  # -1 means: older than.
       super.tuxedo-rs.overrideAttrs (superPrevAttrs: rec {
         version = ver;
         src = superPrevAttrs.src.override {
           rev = "388e5fc96c38412e3640759ba8a1a80dfff1218a";
           hash = "sha256-5F9Xo+tnmYqmFiKrKMe+EEqypmG9iIvwai5yuKCm00Y=";
         };
         cargoDeps = superPrevAttrs.cargoDeps.overrideAttrs (depsPrevAttrs: {
           inherit src;
           name = replaceStrings [superPrevAttrs.version] [version] depsPrevAttrs.name;
           outputHash = "sha256-4guYTjI3NmM/VsY6fbBTNOMqEykNh7opu4nMoihpziE=";
         });
       });
     tailor-gui =
       assert super.tailor-gui.version == self.tuxedo-rs.version;
       super.tailor-gui.overrideAttrs (superPrevAttrs: rec {
         cargoDeps = superPrevAttrs.cargoDeps.overrideAttrs (_depsPrevAttrs: {
           outputHash = "sha256-Mr7gz8GDM+dzwjjIIs0L65ij1euOcC7baJdOzguVsz0=";
         });
       });
   }))

  # Rust pre-built toolchains from official static.rust-lang.org.
  (self: super: let
    oxalica = import <oxalica-rust-overlay>;  # From channel that I added.
  in
    assert ! (super ? rust-bin);
    {
      inherit (oxalica self super) rust-bin;  # (Exclude its other attributes, for now.)
    })

  # Subversion client with support for storing passwords in the D-Bus Secret Service API.
  # TODO: Maybe contribute (something like) this to the official Nixpkgs package.
  (self: super: let
    flag = "--with-gnome-keyring";  # Actually is "with libsecret support".
  in {
    subversionClient = super.subversionClient.overrideAttrs (previousAttrs:
      assert ! (elem flag previousAttrs.configureFlags);
      {
        nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [self.pkg-config self.makeWrapper];
        buildInputs       = previousAttrs.buildInputs       ++ [self.libsecret];
        configureFlags    = previousAttrs.configureFlags    ++ [flag];
        postFixup =
          assert ! (previousAttrs ? postFixup);
          ''
            for x in $out/bin/*; do
              wrapProgram $x --prefix LD_LIBRARY_PATH : $out/lib
            done
          '';
      });
  })

  # Packages with debugging support.  This causes rebuilding of these.
  (self: super: let
    inherit (super) myLib;
    inherit (deps self super) debuggingSupportConfig;

    selection = {
      inherit (super)
        hello  # Have this to always exercise my Nix library for debugging support.
        # You may add more here:
      ;
    };
  in (myLib.pkgWithDebuggingSupport.byMyConfig debuggingSupportConfig).overlayResult selection)
]
