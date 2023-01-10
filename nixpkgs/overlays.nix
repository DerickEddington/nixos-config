# This file, being separate, enables using the same overlays for the NixOS system configuration
# (which affects operations like `nixos-rebuild`) and for the users' configurations (which affects
# operations like `nix-env` and `home-manager`) that also import this file.

deps:  # `deps` is a function that returns dependencies for here, given a `self` and `super` pair.

let
  inherit (builtins) elem match;
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

  # Subversion client with support for storing passwords in GNOME Keyring.
  # TODO: Maybe contribute (something like) this to the official Nixpkgs package.
  (self: super: let
    flag = "--with-gnome-keyring";
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

  # GNU Hello program with debug info.
  (self: super: {
    hello = self.enableDebugging super.hello;
  })
]
