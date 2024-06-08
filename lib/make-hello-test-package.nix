# An altered "hello" package.  Can be useful for testing.

{ myLib, ... }:

let
  inherit (myLib) isDisjoint;
in

pkgs:

let
  configureFlags = [
    "--program-transform-name=s/hello/my-hello-test/"
    "--disable-nls"
  ];
in

pkgs.hello.overrideAttrs
  (origAttrs: let
    origConfigureFlags = origAttrs.configureFlags or [];
  in
    assert isDisjoint configureFlags origConfigureFlags;
    assert ! origAttrs ? preConfigurePhases;
    assert ! origAttrs ? myHelloTest_renameSourceRoot;
    {
      pname = "my-hello-test";
      meta.mainProgram = "my-hello-test";
      configureFlags = origConfigureFlags ++ configureFlags;
      preConfigurePhases = ["myHelloTest_renameSourceRoot"];
      myHelloTest_renameSourceRoot = ''
        mv -v ../"$sourceRoot" ../"''${sourceRoot/hello/my-hello-test}"
        export sourceRoot="''${sourceRoot/hello/my-hello-test}"
      '';
      doCheck = false;  # Its tests assume its program name is not transformed.
    })
