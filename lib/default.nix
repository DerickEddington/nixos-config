# My own library of helpers.
# This can also be imported by users' ~/.config/nixpkgs/my/lib/.

{ pkgs, lib }:

{
  sourceCodeOfPackage = import ./source-code-of-package.nix { inherit pkgs lib; };
}
