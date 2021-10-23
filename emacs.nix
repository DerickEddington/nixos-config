{ pkgs ? import <nixpkgs> {} }:

let
  baseEmacs = pkgs.emacs;
  emacsWithPackages = (pkgs.emacsPackagesFor baseEmacs).emacsWithPackages;
in
  emacsWithPackages (epkgs: (with epkgs.melpaPackages; [
      ivy
      counsel
      ivy-hydra
      lsp-ivy
      rg
      ibuffer-project
      home-end
      all-the-icons
      cargo
      lsp-mode
      lsp-ui
      magit
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
    ]) ++ (with epkgs.elpaPackages; [
      gnu-elpa-keyring-update
    ])
  )
