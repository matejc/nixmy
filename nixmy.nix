{ pkgs, nixmyConfig, branchPrefix ? "mylocal" }:
let
  cfg = nixmyConfig;

  NIX_PATH = "nixpkgs=${cfg.nixpkgs}:nixos=${cfg.nixpkgs}/nixos:nixos-config=${cfg.nixosConfig}";

  nixmyEnv = pkgs.buildEnv {
    name = "nixmyEnv";
    paths = [ pkgs.wget pkgs.git pkgs.gawk pkgs.coreutils pkgs.gnugrep cfg.nix ] ++ cfg.extraPaths;
  };

  nixmy = pkgs.writeScriptBin "nixmy" ''
    #!${pkgs.stdenv.shell}

    set -e

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

    upgrade() {
        cd ${cfg.nixpkgs}

        if ! update
        then
            echo "Update failed!" >&2
            return 1
        fi

        local diffoutput="$(git --no-pager diff)"
        if [ -z "$diffoutput" ]
        then
            local branchNum="$(pull)"
            local pullExitCode=$?
            if [[ pullExitCode -ne 0 ]]
            then
                echo "Pull failed!" >&2
                return 1
            fi
            local branch="${branchPrefix}$branchNum"
            local commits=$(git rev-list --left-only --count local...$branch)
            if [[ "$commits" == "0" ]]
            then
                echo "There are no new commits in local branch, no need to update!" >&2
                return 0
            fi
            local newBranch="${branchPrefix}$(( branchNum + 1 ))"
            git checkout -b "$newBranch"
            echo "Rebase local -> $newBranch ..."
            git rebase local
        else
            git status
            echo "STAGE IS NOT CLEAN! CLEAR IT BEFORE UPDATE!" >&2
            return 1
        fi
    }

    pull() {
        cd ${cfg.nixpkgs}

        echo "Fetching origin ..." >&2
        git fetch origin >&2
        local branchNum=$(git branch --all --list --format '%(refname:short)' | awk 'match($0, /^(origin\/)?${branchPrefix}([0-9]+)$/, g) {print g[2]}' | sort -n -r | head -n1)
        if [ -z "$branchNum" ]
        then
            echo "No branches found with pattern: /${branchPrefix}[0-9]+/!" >&2
            return 1
        fi
        local branch="${branchPrefix}$branchNum"
        git checkout "$branch" >&2
        echo $branchNum
    }

    push() {
        cd ${cfg.nixpkgs}

        local branchNum=$(git branch --all --list --format '%(refname:short)' | awk 'match($0, /^(origin\/)?${branchPrefix}([0-9]+)$/, g) {print g[2]}' | sort -n -r | head -n1)
        if [ -z "$branchNum" ]
        then
            echo "No branches found with pattern: /${branchPrefix}[0-9]+/!" >&2
            return 1
        fi
        local branch="${branchPrefix}$branchNum"
        git checkout "$branch"
        git push --atomic origin "local:local" "$branch"
        git push origin "$branch:latest" -f
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
        ${pkgs.nix-index}/bin/nix-locate $@
    }

    tree() {
        ${pkgs.nix-tree}/bin/nix-tree $@
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
        if [ -z "''${2-}" ]
        then
            ${cfg.nix}/bin/nix-shell -p $(echo "$1" | tr ',' ' ') --run "$SHELL"
        else
            args="''${*:2}"
            ${cfg.nix}/bin/nix-shell -p $(echo "$1" | tr ',' ' ') --run "$SHELL -c \"$args\""
        fi
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
        git clone "${cfg.backup}" "$backupDir"
        backupNixDir="$HOME/.nixmy/backup/$(cat /etc/hostname)/"
        mkdir -p $backupNixDir
        cp -rv "$(dirname ${cfg.nixosConfig})/"* "$backupNixDir"
        git -C "$backupDir" add "$backupNixDir"
        git -C "$backupDir" commit -m "Backup from $(cat /etc/hostname)"
        git -C "$backupDir" push origin master
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

    stray-roots() {
        ${cfg.nix}/bin/nix-store --gc --print-roots | egrep -v "^(/nix/var|/run/\w+-system|\{memory|/proc)"
    }

    clean() {
        ${cfg.nix}/bin/nix-collect-garbage -d $@
    }

    check() {
        ${pkgs.hydra-check}/bin/hydra-check "$*"
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
