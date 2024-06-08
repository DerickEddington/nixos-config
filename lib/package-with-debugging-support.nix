# TODO(nix-bug): The commented-out lines below marked w/ TODO(nix-bug) should be uncommented to be
# reactivated in the future once the bug in the Nix evaluation of `assert` is fixed.  The bug
# causes those asserts to always "fail" even when their expression's value is true.

{ pkgs, lib, ... }:

let
  inherit (builtins) elem match mapAttrs;
  inherit (lib) optional;
  inherit (lib.attrsets) optionalAttrs;
  inherit (pkgs) enableDebugging;

  absoluteSourceRoot = "$NIX_BUILD_TOP/$sourceRoot";
in

rec {
  __functor = self: self.byArgs;  # Make this attribute set callable.

  byArgs =
    { namePrefix ? false
    , debugInfo ? "together-Og"
    , sourceCode ? true
    , srcTopDir ? "src/of-pkg-via-my"
    , omitUnneeded ? false
    , addOutputsToInstall ? true
    }:

    let
      haveNamePrefix = namePrefix != false;
      wantDebugInfo = debugInfo != false;
      separateDebugInfo = wantDebugInfo && (match "separate.*" debugInfo) != null;
      togetherDebugInfo = wantDebugInfo && (match "together.*" debugInfo) != null;
      onlySrcOutput = sourceCode && omitUnneeded && !wantDebugInfo;
      needAllPhases = wantDebugInfo || !omitUnneeded;
    in

      # Either or both of these must be given.  (Else this function shouldn't be used.)
      assert sourceCode || wantDebugInfo;
      # Sanity checks.
      assert separateDebugInfo || togetherDebugInfo -> separateDebugInfo == !togetherDebugInfo;
      assert onlySrcOutput -> !needAllPhases;

      pkg:

      let
        overriddenPkg =
          pkg.overrideAttrs (origAttrs:
            # Note: In some places below, `pkg` is used instead of `origAttrs`, to get an original
            # value, because this ensures we use the same values as determined by `mkDerivation`
            # which sometimes computes values that are different than what is in `origAttrs`
            # (e.g. for defaults where `origAttrs` is missing something).
            let
              other = {
                outputs            = origAttrs.outputs or ["out"];
                phases             = origAttrs.phases or [];
                preConfigurePhases = origAttrs.preConfigurePhases or [];
                preBuildPhases     = origAttrs.preBuildPhases or [];
                postPhases         = origAttrs.postPhases or [];
              };
              unusedOutput = name:
                !(elem name other.outputs) && !(origAttrs ? name);
              unusedPhase = name: given:
                !(elem name other.phases) && !(elem name other.${given}) && !(origAttrs ? name);

              namePrefixAttrs = optionalAttrs haveNamePrefix
                (let
                  rename = name: "${namePrefix}-${name}";
                in
                  if pkg ? name
                  then { name = rename pkg.name; }
                  else if pkg ? pname
                  then { pname = rename pkg.pname; }
                  else { pname = rename "unnamed"; });

              sourceCodeAttrs = optionalAttrs sourceCode {
                outputs =
                  # I assume that "srcasused" is not an output name used by Nixpkgs and so I may
                  # use it myself.
                  # TODO(nix-bug)  assert unusedOutput "srcasused";
                  if onlySrcOutput
                    # Have our custom output as the default (first).  Keep the original outputs
                    # because they can affect how a package's source is prepared
                    # (e.g. _multioutConfig of Nixpkgs).
                  then ["srcasused"] ++ other.outputs
                    # Have it as last, for other cases.
                  else other.outputs ++ ["srcasused"];

                # Rename the $sourceRoot if it's not named according to the package name and
                # version, but only when we will be rebuilding it anyway.  This produces better
                # debug-info about the source-files' compilation directory (instead of that being
                # something like only /build/source which can cause conflicts when multiple such
                # packages are installed and these source files need to be linked from
                # /run/current-system/sw/src/ or ~/.nix-profile/src/).
                preConfigurePhases =
                  # TODO(nix-bug)  assert unusedPhase "myDebugSupport_renameSourceRoot" "preConfigurePhases";
                  other.preConfigurePhases ++ ["myDebugSupport_renameSourceRoot"];
                myDebugSupport_renameSourceRoot = let
                  isRebuilding = needAllPhases;
                  pkgName = pkg.name or (if pkg ? pname
                                         then (if pkg ? version
                                               then "${pkg.pname}-${pkg.version}"
                                               else pkg.pname)
                                         else "");
                  srcName = if pkgName != "" then pkgName else "$name";
                in
                  # TODO: This probably will not work for all packages, especially those that
                  # build from unusual directory structures.
                  if isRebuilding then ''
                    if ! [[ "${absoluteSourceRoot}" = *"${srcName}"* ]]; then
                      myDebugSupport_temp="$(mktemp -d -p "$NIX_BUILD_TOP")"
                      mv -v "${absoluteSourceRoot}" "$myDebugSupport_temp"/
                      mkdir "${absoluteSourceRoot}"
                      mv -v "$myDebugSupport_temp/$(basename "${absoluteSourceRoot}")" \
                            "${absoluteSourceRoot}/${srcName}"
                      export sourceRoot+="/${srcName}"
                      rmdir "$myDebugSupport_temp"
                      unset myDebugSupport_temp
                    else
                      echo "not renaming because \$sourceRoot contains '${srcName}'"
                    fi
                  ''
                  else ''
                    echo "not rebuilding so not considering renaming \$sourceRoot"
                  '';

                # Use preBuildPhases because it's run after patchPhase,configurePhase,etc and it's
                # run before buildPhase,etc, which allows us to capture the package's source-code
                # in the state as prepared for the package.  Place my phase after any others of
                # origAttrs.preBuildPhases, in case we should capture any changes those others
                # might make.  Add my own phase as opposed to a hook, to avoid messing with other
                # phases' hooks.
                preBuildPhases =
                  # I assume that "myDebugSupport_saveSrcPhase" is not a phase name used by
                  # Nixpkgs and so I may use it myself.
                  # TODO(nix-bug)  assert unusedPhase "myDebugSupport_saveSrcPhase" "preBuildPhases";
                  other.preBuildPhases ++ ["myDebugSupport_saveSrcPhase"];

                # The goal.  Copy the prepared source-code to our output.  Preserve its directory
                # structure starting from its top, because that usually corresponds to the
                # source-file-name paths recorded in the debug-info generated for the actual
                # package's binaries, which enables debuggers like GDB to find these source files
                # when /run/current-system/sw/src/of-pkg-via-my (or
                # ~/.nix-profile/src/of-pkg-via-my, or ./result-srcasused/src/of-pkg-via-my, etc)
                # is configured to be in the "source path" of the debugger (e.g. by ~/.gdbinit
                # using `dir`).
                myDebugSupport_saveSrcPhase = let
                  destDir = "$srcasused/${srcTopDir}/${absoluteSourceRoot}";
                in ''
                  mkdir -v -p "$(dirname "${destDir}")"
                  echo "Copying ${absoluteSourceRoot} ..."
                  cp -a "${absoluteSourceRoot}" "${destDir}"
                '';
              };

              debugInfoAttrs = optionalAttrs wantDebugInfo
                (if togetherDebugInfo
                 then {}  # We use enableDebugging below to achieve "together".
                 else if separateDebugInfo
                 then { separateDebugInfo = true; }
                 else throw "Unrecognized debugInfo variant");

              phasesAttrs = optionalAttrs onlySrcOutput {
                # Skip all phases that are after the source-code has been prepared.
                dontBuild = true;
                doCheck = false;
                dontInstall = true;
                dontFixup = true;
                doInstallCheck = false;
                doDist = false;

                # To satisfy the Nix building logic, all outputs must be produced.
                # This also skips any origAttrs.postPhases, by not including those.
                postPhases =
                  # I assume that "myDebugSupport_makeOrigOutputsPhase" is not a phase name used
                  # by Nixpkgs and so I may use it myself.
                  # TODO(nix-bug)  assert unusedPhase "myDebugSupport_makeOrigOutputsPhase" "postPhases";
                  ["myDebugSupport_makeOrigOutputsPhase"];

                myDebugSupport_makeOrigOutputsPhase = ''
                  for o in $outputs ; do touch -a ''${!o} ; done
                '';
              };

              outputsToInstallAttrs =
                let
                  addDebugOutput = separateDebugInfo && !(elem "debug" pkg.meta.outputsToInstall);
                  addSrcOutput = sourceCode && !(elem "srcasused" pkg.meta.outputsToInstall);
                  needMeta = addOutputsToInstall && (addDebugOutput || addSrcOutput);
                in
                  optionalAttrs needMeta
                    (let
                      debugOutputs = optional addDebugOutput "debug";
                      srcOutputs = optional addSrcOutput "srcasused";
                      outputsToInstall =
                        if onlySrcOutput then
                          # Omit all outputs except our source-code output.
                          srcOutputs
                        else
                          # Don't omit any outputs, because debug-info only makes sense with
                          # having the corresponding binaries.
                          pkg.meta.outputsToInstall ++ debugOutputs ++ srcOutputs;
                    in
                      { meta = pkg.meta // { inherit outputsToInstall; }; });
            in
              namePrefixAttrs // sourceCodeAttrs // debugInfoAttrs // phasesAttrs
              // outputsToInstallAttrs
          );
      in
        if togetherDebugInfo then
          (if debugInfo == "together-Og"
           then enableDebugging overriddenPkg
           else throw "TODO: Unsupported debugInfo variant")
        else
          overriddenPkg;

  # Helps make a Nixpkgs overlay.  Returns an attribute set that is usable as the result of an
  # overlay function.
  overlayResult = args: pkgsSelection:
    mapAttrs (_name: pkg: byArgs args pkg) pkgsSelection;

  # Converts a `my.debugging` option value and uses that as our types of arguments.
  byMyConfig = dbgCfg: let
    enable.debugInfo  = dbgCfg.debugInfo.of.locallyBuilt.enable  or false;
    enable.sourceCode = dbgCfg.sourceCode.of.locallyBuilt.enable or false;
    args = {
      debugInfo = if enable.debugInfo then dbgCfg.debugInfo.of.locallyBuilt.how else false;
      sourceCode = enable.sourceCode;
    };
  in {
    __functor = _self: pkg: byArgs args pkg;  # Make this attribute set callable.

    # pkgsSelection -> attrSet
    overlayResult = let
      needOverride = enable.debugInfo || enable.sourceCode;
    in
      (pkgsSelection:
        mapAttrs (_name: pkg: if needOverride then (byArgs args pkg) else pkg)
          pkgsSelection);
  };
}
