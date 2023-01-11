# Make tmpfiles.d entry rules for systemd-tmpfiles.

{ ... }:

let
  inherit (builtins) substring;
in

{ mode ? "-", user ? "-", group ? "-" }:
path:
let
  pathStr = toString path;
  type-age = if "/tmp/" == (substring 0 5 pathStr)
             then { type = "D!"; age = "10d"; }             # (These use the same cleanup-ages
             else if "/var/tmp/" == (substring 0 9 pathStr) #  as systemd uses.)
             then { type = "q"; age = "30d"; }              #
             else { type = "q"; age = "-"; };
  inherit (type-age) type age;
in
"${type} ${pathStr} ${mode} ${user} ${group} ${age}"
