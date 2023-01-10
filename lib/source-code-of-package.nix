# Package the source-code of a package as used to build that package.  Especially useful when
# debugging, because the source files must be the same as those that were used to build what is
# being debugged, and so they must have all the patches (and any other modifications) that are
# applied when building a package.  (I.e. the src attribute of a derivation would not be
# appropriate to use with debugging because the src's files often are patched for the Nixpkgs
# package and so there could be mismatches between the built package's binaries and the unpatched
# source files.)

{ pkgs, lib, myLib, ... }:

let
  inherit (builtins) elemAt intersectAttrs match;
  inherit (lib.attrsets) genAttrs;
  inherit (myLib) pkgWithDebuggingSupport;
  inherit (pkgs) buildEnv;

  topDir = "src/of-pkg-via-my";
  namePrefixOfPrepared = "prepared-source-of";

  # Make our result have only a single typical "out" output.  This avoids problems with some
  # things trying to use the other unusual empty-file outputs of sourceCodeOnlyDerivation.
  encapsulateSingleOutput = drvOutput:
    assert drvOutput.outputSpecified or false;  # Must give an explicit output.
    buildEnv {
      name = let rename = name: let m = match "${namePrefixOfPrepared}-(.+)" name;
                                    n = elemAt m 0;  # (Error if not matched.)
                                in "source-of-${n}";
             in rename drvOutput.name;
      paths = [drvOutput];
      pathsToLink = ["/${topDir}"];
      meta = let
        # Keep only the attributes that we know don't cause undesired effects and that make sense.
        keepNames = ["longDescription" "homepage" "downloadPage" "changelog" "license"];
        keepAttrs = genAttrs keepNames (_: null);
        keep = intersectAttrs keepAttrs drvOutput.meta;
      in
        keep // { description = "Source-code of: ${drvOutput.description or "Something"}"; };
    };

  commonArgs = {
    sourceCode = true;
    srcTopDir = topDir;
  };
in

{
  # Extend a package to also contain its source-code along with the rest of it, and optionally to
  # be built with debug-info.
  add = { debugInfo ? false }: pkg:
    pkgWithDebuggingSupport
      (commonArgs // {
        namePrefix = "debugging-support-for";
        inherit debugInfo;
        omitUnneeded = false;
      })
      pkg;

  # Create a derivation containing only the source-code of the given package and nothing else.
  only = pkg:
    let
      sourceCodeOnlyDerivation =
        pkgWithDebuggingSupport
          (commonArgs // {
            namePrefix = namePrefixOfPrepared;
            debugInfo = false;
            omitUnneeded = true;
          })
          pkg;
    in
      encapsulateSingleOutput sourceCodeOnlyDerivation.srcasused;
}
