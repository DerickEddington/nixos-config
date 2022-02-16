# This file, being separate, enables using the same overlays for the NixOS
# system configuration (which affects operations like nixos-rebuild) and for the
# users' configurations (which affects operations like nix-env) that also import
# this file.

let
  inherit (builtins) match;
in

[
  # Make the nixos-unstable channel available as pkgs.unstable, for stable
  # versions of pkgs only.
  (self: super: let
    inherit (super) lib;
    isStableItself = isNull (match "pre.*" lib.trivial.versionSuffix);
  in
    if isStableItself then
      {
        unstable = assert ! (super ? unstable);
          # Pass the same config so that attributes like allowUnfreePredicate
          # are propagated.
          import <nixos-unstable> { inherit (self) config; };
      }
    else {})

  # Add the Comix Cursors mouse themes.
  # TODO: Until comixcursors is in nixpkgs, must use my external package.
  #       Once it is in nixos-unstable, that should become the source.
  #       Once it is in nixpkgs, this overlay should be deleted.
  (self: super: {
    comixcursors = assert ! (super ? comixcursors);
      super.callPackage (fetchGit {
        url = https://github.com/DerickEddington/nix-comixcursors.git;
        ref = "main";
      }) {};
  })
]
