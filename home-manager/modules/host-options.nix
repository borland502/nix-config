{lib, ...}: {
  options.nixConfig.host = {
    isWsl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this home runs in WSL.";
    };
    isNixos = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this home is integrated with NixOS.";
    };
    preferSystemPython = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prefer the host distribution's Python over nixpkgs Python.";
    };
  };
}
