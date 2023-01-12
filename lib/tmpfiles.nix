# Make tmpfiles.d entry rules for systemd-tmpfiles.

{ pkgs, lib, myLib, ... }:

let
  inherit (builtins) replaceStrings stringLength substring;
  inherit (lib.trivial) toHexString;
  inherit (lib.strings) concatMapStringsSep toLower;
  inherit (lib.lists) range;
  inherit (myLib) isAbsolutePath;
  inherit (pkgs) writeTextFile;
in

rec {
  mkRule = { mode ? "-", user ? "-", group ? "-" }: path: let
    pathStr = toString path;
    type-age = if "/tmp/" == (substring 0 5 pathStr)
               then { type = "D!"; age = "10d"; }             # (These use the same cleanup-ages
               else if "/var/tmp/" == (substring 0 9 pathStr) #  as systemd uses.)
               then { type = "q"; age = "30d"; }              #
               else { type = "q"; age = "-"; };
    inherit (type-age) type age;
  in
    "${type} ${pathStr} ${mode} ${user} ${group} ${age}";

  mkDirPkg = let
    dashify = path: let r = replaceStrings ["/"] ["-"] (toString path);
                    in if isAbsolutePath path then substring 1 (stringLength r) r else r;
  in
    (ruleArgs: subDirs: path: let
      destPath = "/lib/tmpfiles.d/my-${dashify path}.conf";
    in {
      pkg = writeTextFile {
        name = "${dashify path}-tmpfiles";
        destination = destPath;
        text = ''
          ${mkRule ruleArgs path}
          ${concatMapStringsSep "\n" (e: mkRule ruleArgs (path + "/${toString e}"))
                                     subDirs}
        '';
      };
      inherit destPath;
    });

  debugging = rec {
    buildID.hexDirs = let
      hexDirs = map (i: let s = toLower (toHexString i);
                        in if stringLength s < 2 then "0" + s else s)
                    (range 0 255);
    in
      map (x: ".build-id/${x}") hexDirs;

    mkDebugInfoDirPkg  = ruleArgs: mkDirPkg ruleArgs buildID.hexDirs;
    mkSourceCodeDirPkg = ruleArgs: mkDirPkg ruleArgs ["build"];
  };
}
