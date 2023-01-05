{ pkgs, lib, ... }:

{
  _module.args = {
    # Provide my own library of helpers.
    myLib = import ./lib { inherit pkgs lib; };
  };
}
