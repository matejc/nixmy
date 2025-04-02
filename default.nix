{ pkgs, lib, config, ... }:
with lib;
let
  cfg = config.programs.nixmy;
in {
  options.programs.nixmy = {
    enable = mkEnableOption "Enable nixmy";

    nixpkgsLocalPath = mkOption {
      type = types.str;
      description = "Path to your nixpkgs on filesystem";
    };

    nixpkgsRemote = mkOption {
      type = types.str;
      description = "Your git nixpkgs fork";
    };

    backupRemote = mkOption {
      type = types.str;
      description = "Your nixos configuration backup git repo";
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
    environment.systemPackages = [ (import ./nixmy.nix { inherit pkgs; inherit (cfg) nixpkgsLocalPath nixpkgsRemote backupRemote extraPaths nix; }) ];
  };
}
