{ pkgs ? import <nixpkgs> {} }:

let
  emacsOrig = pkgs.emacs;
  epkgsOrig = emacsOrig.pkgs;

  # Use the latest list of what MELPA has, so that updated versions of Emacs
  # packages in MELPA are available to us sooner.  The stable <nixos> channel is
  # not updated after release, whereas the <nixos-unstable> channel is
  # continually updated.
  latestMelpaArchive = let
    channel = <nixos-unstable>;
    pkg = "pkgs/applications/editors/emacs";
    archive = "elisp-packages/recipes-archive-melpa.json";
  in
    channel + "/${pkg}/${archive}";

  melpaOverride = { archiveJson = latestMelpaArchive; };

  # This `overrides` used with `overrideScope'` causes these exact emacs-package
  # derivations (that are our custom "latest MELPA" ones) to also be used to
  # satisfy the dependencies of any emacs-packages that depend on these
  # emacs-packages' names.  Otherwise, multiple versions of some emacs-packages
  # might be installed, e.g. the latest `ivy` that we give here and another
  # older-version `ivy` (from the original emacs-packages set) since `counsel`
  # also depends on it.  That is avoided by this overriding, e.g. only the
  # single latest `ivy` is installed and is also used for the dependency of
  # `counsel`.
  overrides = self: super:
    let
      melpaPackages       = super.melpaPackages.override       melpaOverride;
      melpaStablePackages = super.melpaStablePackages.override melpaOverride;
    in
      # All from latest MELPA Stable.
      melpaStablePackages //
      # All from latest MELPA Unstable, with higher priority than MELPA Stable.
      melpaPackages //
      # Particular ones from latest MELPA Stable, with higher priority than
      # MELPA Unstable.
      {
        inherit (melpaStablePackages)
          magit
        ;
      } //
      { inherit melpaStablePackages melpaPackages; };

  # My selection of emacs-packages, from my overrides above, pre-installed in
  # this Emacs derivation/package.
  emacsLatestMelpa = (epkgsOrig.overrideScope' overrides).withPackages
    (epkgs: with epkgs; [
      adaptive-wrap
      all-the-icons
      cargo
      company
      counsel
      expand-region
      flycheck
    # gnu-elpa-keyring-update
      go-mode
      home-end
      ibuffer-project
      ivy
      ivy-hydra
      lsp-ivy
      lsp-mode
      lsp-ui
      magit
      multiple-cursors
      nasm-mode
      nix-mode
      rg
      rust-mode
      smartparens
      toml-mode
    ]);
in
emacsLatestMelpa
