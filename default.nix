{ pkgs, lib, nixmyConfig, ... }:
let
  cfg = nixmyConfig;

  NIX_PATH = "nixpkgs=${cfg.nixpkgs}:nixos=${cfg.nixpkgs}/nixos:nixos-config=${cfg.nixosConfig}";

  # this is a command and not a function, to work with nox
  nixenv = pkgs.writeScriptBin "nixenv" ''
    #!${pkgs.stdenv.shell}
    ${cfg.nix}/bin/nix-env -f "${cfg.nixpkgs}" "$@"
  '';

  nixmyEnv = pkgs.buildEnv {
    name = "nixmyEnv";
    paths = [ pkgs.wget pkgs.git nixenv cfg.nix ] ++ cfg.extraPaths;
  };

  nixmy = pkgs.writeScriptBin "nixmy" ''
    #!${pkgs.stdenv.shell}

    export NIX_PATH="${NIX_PATH}"
    export PATH="${nixmyEnv}/bin:$PATH"

    profile() {
        ${cfg.nix}/bin/nix-env $2 -f "${cfg.nixpkgs}" -p /nix/var/nix/profiles/per-user/"$USER"/"$1" -i "$1";
    }

    log() {
        git -C ${cfg.nixpkgs} log --graph --decorate --pretty=oneline --abbrev-commit --branches --remotes --tags ;
    }

    rebuild() { nixos-rebuild -I 'nixpkgs=${cfg.nixpkgs}' "$@" ; }

    rebuild-flake() { nixos-rebuild "$1" --flake "$2" ''${@:3} ; }

    revision() {
      local rev=`${pkgs.curl}/bin/curl -sL https://nixos.org/channels/nixos-unstable | grep -Po "(?<=/commits/)[^']*"`
      printf "%s" $rev
    }

    update() {
        cd ${cfg.nixpkgs}

        local diffoutput="`git --no-pager diff`"
        if [ -z "$diffoutput" ]; then
            {
                echo "git diff is empty, proceeding ..." &&
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
            cd $(dirname ${cfg.nixpkgs}) # go one directory back to root of destination (/nixpkgs will be created by git clone)
            git clone ${cfg.nixpkgs} nixpkgs &&
            cd nixpkgs &&
            git remote add upstream https://github.com/NixOS/nixpkgs.git &&
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
      ${cfg.nix}/bin/nix-instantiate --eval -E "let p = import <nixpkgs> {}; in toString p.$1" | sed "s/\"//g"
    }

    find() {
      ${pkgs.findutils}/bin/find /nix/store -iname "$@"
    }

    locate() {
      ${pkgs.findutils}/bin/locate -i "$@"
    }

    query() {
      ${cfg.nix}/bin/nix-env -f "${cfg.nixpkgs}" -qaP --description | grep -i $@
    }

    installed() {
      ${cfg.nix}/bin/nix-env -f "${cfg.nixpkgs}" -q $@
    }

    install() {
      ${cfg.nix}/bin/nix-env -f "${cfg.nixpkgs}" -iA $@
    }

    erase() {
      if [ -z "$1" ]; then
        echo "argument is required"
        exit 1
      else
        ${cfg.nix}/bin/nix-env -f "${cfg.nixpkgs}" -e $@
      fi
    }

    build() {
      ${cfg.nix}/bin/nix-build '<nixpkgs>' -A $1
    }

    just-build() {
      ${cfg.nix}/bin/nix-build '<nixpkgs>' --no-out-link -A $1
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

    run() {
      ${cfg.nix}/bin/nix-shell -p $1 --run "''${@:2}"
    }

    nix_() {
      ${cfg.nix}/bin/nix --extra-experimental-features 'nix-command flakes' $@
    }

    backup() {
      mkdir -p $HOME/.nixmy
      backupDir="$HOME/.nixmy/backup"
      if [ -d "$backupDir" ]
      then
        rm -rf "$backupDir"
      fi
      if [ -z "${cfg.backup}" ]
      then
        echo "backup is not set" >&2
        exit 1
      fi
      ${pkgs.git}/bin/git clone "${cfg.backup}" "$backupDir"
      backupNixDir="$HOME/.nixmy/backup/$(cat /etc/hostname)/"
      mkdir -p $backupNixDir
      cp -rv "$(dirname ${cfg.nixosConfig})/"* "$backupNixDir"
      ${pkgs.git}/bin/git -C "$backupDir" add "$backupNixDir"
      ${pkgs.git}/bin/git -C "$backupDir" commit -m "Backup from $(cat /etc/hostname)"
      ${pkgs.git}/bin/git -C "$backupDir" push origin master
      rm -rf "$backupDir"
    }

    flake-update() {
      flake="$1"
      list="''${@:2}"
      if [[ "$list" == "all" ]]
      then
        list="$(${cfg.nix}/bin/nix-instantiate --eval --json -E "let a = import $flake/flake.nix; in builtins.attrNames a.inputs" | ${pkgs.jq}/bin/jq -r '.[]')"
      fi
      for item in $list
      do
        ${cfg.nix}/bin/nix flake lock --update-input $item "$flake"
      done
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
