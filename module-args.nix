{ pkgs, lib, ... }:

{
  _module.args = {
    # Provide my own library of helpers.
    inherit (pkgs) myLib;  # Depends on my overlays adding it to `pkgs`.
  };
}
