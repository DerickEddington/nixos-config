{ pkgs, ...}:

{
  environment = {
    systemPackages = with pkgs; [
      aspell
      aspellDicts.en
      aspellDicts.en-computers
      aspellDicts.en-science
      hunspellDicts.en_US-large  # Mainly for LibreOffice.
    ];

    # Needed because NixOS no longer automatically exports ASPELL_CONF, and its new patching of
    # Aspell to use $NIX_PROFILES seems to not work.
    variables.ASPELL_CONF = "conf-dir /etc";

    etc."aspell.conf".text = ''
      # This requires that the env var ASPELL_CONF is defined to use this file,
      # which is done by my custom NixOS module.

      # Use the union of whatever multiple packages provide.
      data-dir /run/current-system/sw/lib/aspell

      # Requires aspellDicts.en-computers package
      add-extra-dicts en-computers.rws
      # Requires aspellDicts.en-science package
      add-extra-dicts en_US-science.rws
    '';
  };
}
