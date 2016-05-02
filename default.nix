/*
  Minimal example (/etc/nixos/configuration.nix):

  nixpkgs.config.nixmy = {
    NIX_MY_PKGS = "/home/matej/workarea/nixpkgs";
    NIX_USER_PROFILE_DIR = "/nix/var/nix/profiles/per-user/matej";
    NIX_MY_GITHUB = "git://github.com/matejc/nixpkgs.git";
  };
*/

{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, config ? pkgs.config }:
let
  # required, see above for example
  NIX_MY_PKGS = config.nixmy.NIX_MY_PKGS;
  NIX_USER_PROFILE_DIR = config.nixmy.NIX_USER_PROFILE_DIR;
  NIX_MY_GITHUB = config.nixmy.NIX_MY_GITHUB;

  # optional
  NIXOS_CONFIG = config.nixmy.NIXOS_CONFIG or "/etc/nixos/configuration.nix";
  NIXOS_SERVICES = config.nixmy.NIXOS_SERVICES or "/etc/nixos/services";

  # if you want to use nox for your custom nixpkgs
  useNox = config.nixmy.useNox or true;

  # to add other programs to nixmy
  extraPaths = config.nixmy.extraPaths or [];

  nix = config.nixmy.nix or config.nix.package or pkgs.nix;
  NIX_PATH = "nixpkgs=${NIX_MY_PKGS}:nixos=${NIX_MY_PKGS}/nixos:nixos-config=${NIXOS_CONFIG}:services=${NIXOS_SERVICES}";

  # this is a command and not a function, to work with nox
  nixenv = pkgs.writeScriptBin "nix-env" ''
    #!${pkgs.stdenv.shell}
    ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" "$@"
  '';

  nixmyEnv = pkgs.buildEnv {
    name = "nixmyEnv";
    paths = [ nixenv pkgs.wget pkgs.git ]
      ++ (lib.optionals useNox [ pkgs.nox ])
      ++ extraPaths;
  };

  nixmy = pkgs.writeScriptBin "nixmy" ''
    #!${pkgs.stdenv.shell}

    export NIX_PATH="${NIX_PATH}"
    export PATH="${nixmyEnv}/bin:$PATH"

    profile() {
        ${nix}/bin/nix-env $2 -f "${NIX_MY_PKGS}" -p ${NIX_USER_PROFILE_DIR}/"$1" -i "$1";
    }

    log() {
        git -C ${NIX_MY_PKGS} log --graph --decorate --pretty=oneline --abbrev-commit --branches --remotes --tags ;
    }

    rebuild() { nixos-rebuild -I 'nixpkgs=${NIX_MY_PKGS}' "$@" ; }

    # Print latest Hydra's revision
    revision() {
      local rev=`wget -q  -S --output-document - http://nixos.org/channels/nixos-unstable/ 2>&1 | grep Location | awk -F '/' '{print $7}' | awk -F '.' '{print $3}'`
      printf "%s" $rev
    }
    revision-14() {
      local rev=`wget -q  -S --output-document - http://nixos.org/channels/nixos-14.12/ 2>&1 | grep Location | awk -F '/' '{print $7}' | awk -F '.' '{print $4}'`
      printf "%s" $rev
    }

    update() {
        cd ${NIX_MY_PKGS}

        local diffoutput="`git --no-pager diff`"
        if [ -z $diffoutput ]; then
            {
                echo "git diff is empty, preceding ..." &&
                git checkout master &&
                git pull --rebase upstream master &&
                git checkout "local" &&
                local rev=`revision` &&
                echo "rebasing 'local' to '$rev'" &&
                git rebase $rev &&
                echo "UPDATE done, enjoy!"
            } || {
                echo "ERROR with update!"
                return 1
            }
        else
            git status
            echo "STAGE IS NOT CLEAN! CLEAR IT BEFORE UPDATE!"
            return 1
        fi

    }

    init() {
        {
            cd $(dirname ${NIX_MY_PKGS}) # go one directory back to root of destination (/nixpkgs will be created by git clone)
            git clone ${NIX_MY_GITHUB} nixpkgs &&
            cd nixpkgs &&
            git remote add upstream git://github.com/NixOS/nixpkgs.git &&
            git pull --rebase upstream master &&
            local rev=`revision` &&
            echo "creating local branch of unstable channel '$rev'" &&
            git branch "local" $rev &&
            git checkout "local" &&
            echo "INIT done! You can update with 'nixmy update' and rebuild with 'nixmy rebuild' eg: 'nixmy rebuild build'"
        } || {
            echo "ERROR with init!"
            return 1
        }
    }

    "$@"
  '';

in
  nixmy
