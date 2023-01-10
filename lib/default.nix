# My own library of helpers.  The dependencies (the arguments to this expression-file's function)
# may be given as `null`, to support limited uses of the few parts of this library where those are
# not needed.  This file may be `import`ed by other arbitrary uses independently of the NixOS
# configuration evaluation or of the Nixpkgs evaluation.

{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib or null }:

let
  scope = rec {
    propagate = { inherit pkgs lib myLib; };

    limitedTo = {
      builtins  = import ./limited-to-builtins.nix;     # Only allowed to depend on `builtins`.
      lib       = import ./limited-to-lib.nix lib;      # Only allowed to depend on `lib`.
    };

    myLib =
      limitedTo.builtins // limitedTo.lib //
      {
        inherit limitedTo;

        makeHelloTestPkg                = import ./make-hello-test-package.nix          propagate;
        pkgWithDebuggingSupport         = import ./package-with-debugging-support.nix   propagate;
        sourceCodeOfPkg                 = import ./source-code-of-package.nix           propagate;
      };
  };
in

scope.myLib
