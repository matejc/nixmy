#!/bin/sh

# !!!MODIFY NEXT 3 LINES BEFORE RUNNING ANY COMMANDS!!!
export NIX_MY_PKGS='/home/matej/workarea/nixpkgs'  # where the local repo will be after nixmy-init (note, put /nixpkgs at the end - it will be created by git clone)
export NIX_USER_PROFILE_DIR='/nix/var/nix/profiles/per-user/matej'  # change your user name
export NIX_MY_GITHUB='git://github.com/matejc/nixpkgs.git'  # your nixpkgs git repository

# DO NOT MODIFY BELOW

export NIX_PATH="nixpkgs=$NIX_MY_PKGS:nixos=$NIX_MY_PKGS/nixos:nixos-config=/etc/nixos/configuration.nix:services=/etc/nixos/services"

alias nixmy-cd="cd '$NIX_MY_PKGS'"

alias nix-env="nix-env -f '$NIX_MY_PKGS'"

# Sudo helper
_asroot() {
  case `whoami` in
    root)
      echo "" ;;
    *)
      echo "sudo -H " ;;
  esac
}

nixmy-profile() {
    nix-env -f "$NIX_MY_PKGS" -p $NIX_USER_PROFILE_DIR/"$1" -i "$1" ;
}

nixmy-log() {
    git -C $NIX_MY_PKGS log --graph --decorate --pretty=oneline --abbrev-commit --branches --remotes --tags ;
}

nixmy-rebuild() { `_asroot` nixos-rebuild -I nixpkgs=$NIX_MY_PKGS "$@" ; }

# Print latest Hydra's revision
nixmy-revision() {
  local rev=`wget -q  -S --output-document - http://nixos.org/channels/nixos-unstable/ 2>&1 | grep Location | awk -F '/' '{print $7}' | awk -F '.' '{print $3}'`
  printf "%s" $rev
}
nixmy-revision-14() {
  local rev=`wget -q  -S --output-document - http://nixos.org/channels/nixos-14.12/ 2>&1 | grep Location | awk -F '/' '{print $7}' | awk -F '.' '{print $4}'`
  printf "%s" $rev
}

nixmy-update() {
    cd $NIX_MY_PKGS

    local diffoutput="`git --no-pager diff`"
    if [ -z $diffoutput ]; then
        {
            echo "git diff is empty, preceding ..." &&
            git checkout master &&
            git pull --rebase upstream master &&
            git checkout "local" &&
            local rev=`nixmy-revision` &&
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

nixmy-init() {
    {
        cd $(dirname $NIX_MY_PKGS) # go one directory back to root of destination (/nixpkgs will be created by git clone)
        git clone $NIX_MY_GITHUB nixpkgs &&
        cd nixpkgs &&
        git remote add upstream git://github.com/NixOS/nixpkgs.git &&
        git pull --rebase upstream master &&
        local rev=`nixmy-revision` &&
        echo "creating local branch of unstable channel '$rev'" &&
        git branch "local" $rev &&
        git checkout "local" &&
        echo "INIT done! You can update with nixmy-update and rebuild with nixmy-rebuild eg: nixmy-rebuild build"
    } || {
        echo "ERROR with init!"
        return 1
    }
}
