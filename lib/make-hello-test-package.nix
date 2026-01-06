# An altered "hello" package.  Can be useful for testing.

{ myLib, ... }:

let
  inherit (myLib) isDisjoint;
in

pkgs:

let
  extraConfigureFlags = [
    "--program-transform-name=s/hello/my-hello-test/"
    "--disable-nls"
  ];
in

pkgs.hello.overrideAttrs
  (origAttrs: let
    origConfigureFlags = origAttrs.configureFlags or [];
  in
    assert isDisjoint extraConfigureFlags origConfigureFlags;
    rec {
      pname = "my-hello-test";
      meta.mainProgram = "my-hello-test";
      unpackCmd = ''
        _defaultUnpack "$curSrc"
        mv -v {${origAttrs.pname},${pname}}-${origAttrs.version}
      '';
      configureFlags = origConfigureFlags ++ extraConfigureFlags;
      doCheck = false;  # Its tests assume its program name is not transformed.
    })
