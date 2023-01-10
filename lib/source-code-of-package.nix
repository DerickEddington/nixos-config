# Package the source-code of a package as used to build that package.  Especially useful when
# debugging, because the source files must be the same as those that were used to build what is
# being debugged, and so they must have all the patches (and any other modifications) that are
# applied when building a package.  (I.e. the src attribute of a derivation would not be
# appropriate to use with debugging because the src's files often are patched for the Nixpkgs
# package and so there could be mismatches between the built package's binaries and the unpatched
# source files.)

{ pkgs, lib, ... }:

let
  inherit (builtins) elem elemAt intersectAttrs match;
  inherit (lib.attrsets) genAttrs;
  inherit (pkgs) buildEnv;

  topDir = "src/of-pkg-via-my";
  namePrefixOfPrepared = "prepared-source-of";

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
in

pkg:

let
  sourceCodeOnlyDerivation = pkg.overrideAttrs (origAttrs:
    # I assume that "srcasused" is not an output name used by Nixpkgs and so I may use it myself.
    assert (origAttrs ? outputs) -> (! elem "srcasused" origAttrs.outputs);

    (let
      rename = name: "${namePrefixOfPrepared}-${name}";
    in
      (if (origAttrs ? name)
       then { name = rename origAttrs.name; }
       else if (origAttrs ? pname)
       then { pname = rename origAttrs.pname; }
       else { pname = rename "unnamed"; })
    ) // {
      # Have our custom output as the default (first).  Keep the original outputs because they can
      # affect how a package's source is prepared (e.g. _multioutConfig of Nixpkgs).
      outputs = ["srcasused"] ++ (origAttrs.outputs or ["out"]);
      # Only install our output.
      meta.outputsToInstall = ["srcasused"];
      # Prevent trying to handle a "debug" output.
      separateDebugInfo = false;

      # Use preBuildPhases because it's run after patchPhase,configurePhase,etc and it's run
      # before buildPhase,etc, which allows us to capture the package's source-code in the state
      # as prepared for the package.  Place my phase after any others of origAttrs.preBuildPhases,
      # in case we should capture any changes those others might make.  Add my own phase as
      # opposed to a hook, to avoid messing with other phases' hooks.
      preBuildPhases = (origAttrs.preBuildPhases or []) ++ ["mySourceCodePackage_saveSrcPhase"];
      # The main goal.  Copy the prepared source-code to our output.  Preserve its directory
      # structure starting from its top, because that usually corresponds to the source-file-name
      # paths recorded in the debug-info generated for the actual package's binaries, which
      # enables debuggers like GDB to find these source files when
      # /run/current-system/sw/src/of-pkg-via-my (or ~/.nix-profile/src/of-pkg-via-my, or
      # ./result-srcasused/src/of-pkg-via-my, etc) is configured to be in the "source path" of the
      # debugger (e.g. by ~/.gdbinit using `dir`).
      mySourceCodePackage_saveSrcPhase = let
        absoluteSourceRoot = "$NIX_BUILD_TOP/$sourceRoot";
        destDir = "$srcasused/${topDir}/${absoluteSourceRoot}";
      in ''
        mkdir -v -p "$(dirname "${destDir}")"
        echo "Copying ${absoluteSourceRoot} ..."
        cp -a "${absoluteSourceRoot}" "${destDir}"
      '';

      # Skip all phases that are after the source-code has been prepared.
      dontBuild = true;
      doCheck = false;
      dontInstall = true;
      dontFixup = true;
      doInstallCheck = false;
      doDist = false;

      # To satisfy the Nix building logic, all outputs must be produced.
      # This also skips any origAttrs.postPhases, by not including those.
      postPhases = ["mySourceCodePackage_makeOrigOutputsPhase"];
      mySourceCodePackage_makeOrigOutputsPhase = ''
        for o in $outputs ; do touch -a ''${!o} ; done
      '';
    });
in

# Make our result have only a single typical "out" output.  This avoids problems with some things
# trying to use the other unusual empty-file outputs of sourceCodeOnlyDerivation.
encapsulateSingleOutput sourceCodeOnlyDerivation.srcasused
