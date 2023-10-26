# My design for configuring the provision of debugging support for various kinds of Nix packages.
# This file is also `import`ed by users' configurations (by their copies of
# ./users/dotfiles/.config/home-manager/common/debugging.nix), and so changes to this file might
# impact their use and so must be coordinated across that.

{ config, pkgs, lib, myLib, ...}:

let
  inherit (lib) mkEnableOption mkOption types;

  # The C standard library used by the host machine as configured.  This exists to (hopefully)
  # support the possibility of the configuration being used for a host where it's not
  # `pkgs.glibc`.  I'm not 100% certain if this is the best way, but using `stdenv.cc.libc` seems
  # to be how this is done in Nixpkgs.
  hostLibc = pkgs.stdenv.cc.libc;
in

{
  options.my.debugging = {
    support = {
      all.enable = mkEnableOption "all kinds of debugging support";
      debugInfo = {
        all.enable = mkEnableOption "debug-info of all kinds of packages";
        of = {
          prebuilt.enable = mkEnableOption "pre-saved debug-info of pre-built packages";
          locallyBuilt = {
            enable = mkEnableOption "debug-info of some locally-built packages";
            how = mkOption {
              description = "Variants of how to generate the debug info.";
              type = with types; nullOr (enum ["separate" "together-Og"]);
              default = "separate";
            };
          };
        };
        tmpDirs = mkOption {
          description = "temporary directories for debug-info";
          type = with types; listOf path;
        };
      };
      sourceCode = {
        all.enable = mkEnableOption "source-code of all kinds of packages";
        of = {
          prebuilt = {
            enable = mkEnableOption "source-code of chosen pre-built packages";
            packages = mkOption {
              description = ''
                Source-code of pre-built packages ("binary substitutes").
                This overrides each package's derivation to extract its source code, because that
                is not provided as an "output" nor by the binary substitute.
                Note that this does not cause rebuilding of these packages.
                Typically, the packages given here should already be installed by
                `environment.systemPackages` or by those transitively.
              '';
              type = with types; listOf package;
              default = [];
            };
          };
          locallyBuilt.enable = mkEnableOption "source-code of some locally-built packages";
        };
        tmpDirs = mkOption {
          description = "temporary directories for source-code";
          type = with types; listOf path;
        };
      };
    };
  };

  config = let
    inherit (lib) mkDefault mkIf;
    inherit (myLib) sourceCodeOfPkg;
    inherit (myLib.tmpfiles.debugging) mkDebugInfoDirPkg mkSourceCodeDirPkg;

    cfg = config.my.debugging;
    enabled.anySourceCode = let inherit (cfg.support) sourceCode;
                            in (    sourceCode.all.enable
                                 || sourceCode.of.prebuilt.enable
                                 || sourceCode.of.locallyBuilt.enable);
  in {
    my.debugging = {
      support = {
        debugInfo = {
          all.enable = mkDefault cfg.support.all.enable;
          of.prebuilt.enable     = mkDefault cfg.support.debugInfo.all.enable;
          of.locallyBuilt.enable = mkDefault cfg.support.debugInfo.all.enable;
          tmpDirs = mkDefault (if cfg.support.debugInfo.all.enable
                               then [/tmp/debug /var/tmp/debug]
                               else []);
        };
        sourceCode = {
          all.enable = mkDefault cfg.support.all.enable;
          of = {
            prebuilt = {
              enable = mkDefault cfg.support.sourceCode.all.enable;
              packages = [hostLibc];  # Not mkDefault so this merges unless mkForce'd elsewhere.
            };
            locallyBuilt.enable = mkDefault cfg.support.sourceCode.all.enable;
          };
          tmpDirs = mkDefault (if cfg.support.sourceCode.all.enable
                               then [/tmp/src /var/tmp/src]
                               else []);
        };
      };
    };

    environment = {
      # Automatically install the "debug" output of packages if they have that, and set the
      # NIX_DEBUG_INFO_DIRS environment variable to include them, for GDB to find them.
      enableDebugInfo = cfg.support.debugInfo.of.prebuilt.enable;

      # (Note: We don't care about the order of these when this merges with other definitions of
      # this option, because debug-info is found by unique build-id and so any one of the
      # directories which has it should work.)
      variables.NIX_DEBUG_INFO_DIRS = mkIf (cfg.support.debugInfo.tmpDirs != [])
        (map toString cfg.support.debugInfo.tmpDirs);

      systemPackages = mkIf cfg.support.sourceCode.of.prebuilt.enable
        (map sourceCodeOfPkg.only
             cfg.support.sourceCode.of.prebuilt.packages);

      # My custom approach to providing source-code files places them in derivation outputs at
      # locations like /nix/store/.../src/.  This makes these available system-wide at
      # /run/current-system/sw/src/.
      pathsToLink = mkIf enabled.anySourceCode ["/src"];
    };

    systemd.tmpfiles.packages = let
      ruleArgs = { mode = "1777"; user = "root"; group = "root"; };
      use = f: p: (f ruleArgs p).pkg;
    in
      (map (use mkDebugInfoDirPkg)  cfg.support.debugInfo.tmpDirs) ++
      (map (use mkSourceCodeDirPkg) cfg.support.sourceCode.tmpDirs);
  };
}
