# Basic helpers that only can depend on the standard Nix `builtins`.

let
  inherit (builtins) any elem getEnv pathExists substring;
in

{
  isDisjoint = a: b: ! (any (e: elem e a) b);

  isAbsolutePath = strOrPath: "/" == (substring 0 1 "${toString strOrPath}");

  isDirWithDefault = path: pathExists (path + "/default.nix");

  # Redefine this, instead of using `lib.maybeEnv`, to avoid depending on `lib` because that
  # argument to the ./default.nix expression-file's function sometimes needs to be `null`.
  maybeEnv = name: default:
    let value = getEnv name; in
    if value == "" then default else value;
}
