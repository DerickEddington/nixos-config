{ pkgs, ...}:

{
  environment = {
    systemPackages = with pkgs; [
      (aspellWithDicts (dicts: with dicts; [en en-computers en-science]))
      hunspellDicts.en_US-large  # Mainly for LibreOffice.
    ];
  };

  my.allowedUnfree = [ "aspell-dict-en-science" ];
}
