{ pkgs, lib, config, ... }:
with lib;
let
  cfg = config.programs.nixmy;
in {
  options.programs.nixmy = {
    enable = mkEnableOption "Enable nixmy";

    nixpkgs = mkOption {
      type = types.str;
      description = "Path to your nixpkgs on filesystem";
    };

    remote = mkOption {
      type = types.str;
      description = "Your git nixpkgs fork";
    };

    backup = mkOption {
      type = types.str;
      description = "Your nixos configuration backup git repo";
    };

    nixosConfig = mkOption {
      type = types.str;
      default = "/etc/nixos/configuration.nix";
      description = "Nixos configuration entry point";
    };

    extraPaths = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra packages available for nixmy";
    };

    nix = mkOption {
      type = types.package;
      default = config.nix.package.out;
      description = "Nix package used by nixmy";
    };
  };

  config = {
    environment.systemPackages = [ (pkgs.callPackage ./default.nix { nixmyConfig = cfg; }) ];
  };
}

