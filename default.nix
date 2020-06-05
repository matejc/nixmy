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

  NIX_MY_BACKUP = config.nixmy.NIX_MY_BACKUP;

  # optional
  NIXOS_CONFIG = config.nixmy.NIXOS_CONFIG or "/etc/nixos/configuration.nix";
  NIXOS_SERVICES = config.nixmy.NIXOS_SERVICES or "/etc/nixos/services";

  # to add other programs to nixmy
  extraPaths = config.nixmy.extraPaths or [];

  nix = config.nixmy.nix or config.nix.package.out or pkgs.nix.out;
  NIX_PATH = "nixpkgs=${NIX_MY_PKGS}:nixos=${NIX_MY_PKGS}/nixos:nixos-config=${NIXOS_CONFIG}:services=${NIXOS_SERVICES}";

  # this is a command and not a function, to work with nox
  nixenv = pkgs.writeScriptBin "nixenv" ''
    #!${pkgs.stdenv.shell}
    ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" "$@"
  '';

  nixmyEnv = pkgs.buildEnv {
    name = "nixmyEnv";
    paths = [ pkgs.wget pkgs.git nixenv nix ] ++ extraPaths;
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

    revision() {
      local rev=`${pkgs.curl}/bin/curl -sL https://nixos.org/channels/nixos-unstable | grep -Po "(?<=nixpkgs-channels/commits/)[^']*"`
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

    path() {
      ${nix}/bin/nix-instantiate --eval -E "let p = import <nixpkgs> {}; in toString p.$1" | sed "s/\"//g"
    }

    find() {
      ${pkgs.findutils}/bin/find /nix/store -iname "$@"
    }

    locate() {
      ${pkgs.findutils}/bin/locate -i "$@"
    }

    query() {
      ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" -qaP --description | grep -i $@
    }

    installed() {
      ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" -q $@
    }

    install() {
      ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" -iA $@
    }

    erase() {
      if [ -z "$1" ]; then
        echo "argument is required"
        exit 1
      else
        ${nix}/bin/nix-env -f "${NIX_MY_PKGS}" -e $@
      fi
    }

    build() {
      ${nix}/bin/nix-build '<nixpkgs>' -A $1
    }

    just-build() {
      ${nix}/bin/nix-build '<nixpkgs>' --no-out-link -A $1
    }

    command() {
      fullname="`which $1`"
      whichExitStatus="$?"
      if [ "$whichExitStatus" -eq "0" ]; then
        readlink -f "$fullname"
      else
        echo "$1 not found"
        exit 1
      fi
    }

    backup() {
      mkdir -p $HOME/.nixmy
      backupDir="$HOME/.nixmy/backup"
      if [ -d "$backupDir" ]
      then
        rm -rf "$backupDir"
      fi
      if [ -z "${NIX_MY_BACKUP}" ]
      then
        echo "NIX_MY_BACKUP is empty" >&2
        exit 1
      fi
      ${pkgs.git}/bin/git clone "${NIX_MY_BACKUP}" "$backupDir"
      backupNix="$HOME/.nixmy/backup/$(cat /etc/hostname).nix"
      cp -v "${NIXOS_CONFIG}" "$backupNix"
      ${pkgs.git}/bin/git -C "$backupDir" add "$backupNix"
      ${pkgs.git}/bin/git -C "$backupDir" commit -m "Backup from $(cat /etc/hostname)"
      ${pkgs.git}/bin/git -C "$backupDir" push origin master
      rm -rf "$backupDir"
    }

    help() {
      if [ -z "$1" ]; then
        declare -F | ${pkgs.gawk}/bin/awk '{print "nixmy help "$3}'
      else
        declare -f $1
      fi
    }

    "$@"
  '';

in
  nixmy
