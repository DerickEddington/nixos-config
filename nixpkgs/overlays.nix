# This file, being separate, enables using the same overlays for the NixOS
# system configuration (which affects operations like nixos-rebuild) and for the
# users' configurations (which affects operations like nix-env) that also import
# this file.

let
  inherit (builtins) match;
in

[
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
