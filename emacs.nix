{ pkgs ? import <nixpkgs> {} }:

let
  baseEmacs = pkgs.emacs;
  emacsWithPackages = (pkgs.emacsPackagesFor baseEmacs).emacsWithPackages;

  # Use the latest list of what MELPA has, so that updated versions of Emacs
  # packages in MELPA are available to us sooner.
  latestMelpaArchive = let
    channel = <nixos-unstable>;
    pkg = "pkgs/applications/editors/emacs";
    archive = "elisp-packages/recipes-archive-melpa.json";
  in
    channel + "/${pkg}/${archive}";
  melpaOverride =
    { archiveJson = latestMelpaArchive; };
in
emacsWithPackages
  (epkgs:
    let
      melpaPackages       = epkgs.melpaPackages.override       melpaOverride;
      melpaStablePackages = epkgs.melpaStablePackages.override melpaOverride;
    in
      (with melpaStablePackages; [
        ibuffer-project
        magit
      ]) ++
      (with melpaPackages; [
        ivy
        counsel
        ivy-hydra
        lsp-ivy
        rg
        home-end
        all-the-icons
        cargo
        lsp-mode
        lsp-ui
        multiple-cursors
        smartparens
        flycheck
        flycheck-rust
        rust-mode
        go-mode
        nasm-mode
        company
        toml-mode
        nix-mode
      ]) ++
      (with epkgs.elpaPackages; [
        gnu-elpa-keyring-update
      ])
  )
