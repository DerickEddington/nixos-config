# This file, being separate, enables using the same overlays for the NixOS
# system configuration (which affects operations like nixos-rebuild) and for the
# users' configurations (which affects operations like nix-env) that also import
# this file.

let
  inherit (builtins) match;
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

  # Add the Comix Cursors mouse themes.
  # TODO: Until comixcursors is in stable nixpkgs, use nixos-unstable.
  #       Once it is in stable, this overlay should be deleted.
  (self: super:
    if isStableVersion super then
      {
        comixcursors = assert ! (super ? comixcursors);
          self.unstable.comixcursors;
      }
    else assert (super ? comixcursors); {})
]
