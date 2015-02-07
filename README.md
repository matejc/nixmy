nixmy
=====

NixOS developing made easy

PS: nothing magical, just a nix script with a few useful commands.


Configuration
-------------

Before installing, change the following options!

Example:

    nixpkgs.config.nixmy = {
      NIX_MY_PKGS = "/home/matej/workarea/nixpkgs";
      NIX_USER_PROFILE_DIR = "/nix/var/nix/profiles/per-user/matej";
      NIX_MY_GITHUB = "git://github.com/matejc/nixpkgs.git";
    };


Installation
------------

    environment.systemPackages = [
        .
        .
        .
        (pkgs.callPackage /path/to/nixmy/default.nix { })
    ];


Options
-------

Required:

 - `NIX_MY_PKGS` - where the local repo will be after `nixmy init` (note, put /nixpkgs at the end - it will be created by git clone)
 - `NIX_USER_PROFILE_DIR` - change your user name
 - `NIX_MY_GITHUB` - your nixpkgs git repository


Optionals:

 - `useNox` - if you want to use `pkgs.nox` with nixmy like (default: true)
 - `extraPaths` - extra packages to be available as `nixmy <command>`
 - `NIXOS_CONFIG` - `nixos-config` part of the `NIX_PATH` (default: /etc/nixos/configuration.nix)
 - `NIXOS_SERVICES` - `services` part of the `NIX_PATH` (default: /etc/nixos/services)



nixmy init
----------

After running `nixmy init` you will have nixpkgs directory at `NIX_MY_PKGS` filesystem location.

Git branches:

 - `local` - where you want to be when `nixmy rebuild` is called, as this is your favorite channel (unstable by default)
 - `master` - this is where master branch of git://github.com/NixOS/nixpkgs.git is

Git remotes:

 - `origin` - this is `NIX_MY_GITHUB` - your git repository
 - `upstream` - official repository git://github.com/NixOS/nixpkgs.git


nixmy update
------------

Before running `nixmy update` make sure that you commit or stash changes.
This command will rebase from official master NixOS/nixpkgs git repository to `master` and then rebase your favorite channel to `local` branch.

every now and then you can update your `NIX_MY_GITHUB` repository by pushing to it, ex:

    git checkout master
    git push origin master

do not forget to checkout local branch after as this is your work branch.


nixmy rebuild
-------------

 - `nixmy rebuild` - to rebuild from revision currently checked out inside `NIX_MY_PKGS`

Do forget about `nixos-rebuild` and from now on, use `nixmy rebuild`, usage is the same.


nixmy nix-env
-------------

Shell alias to `nix-env -f '$NIX_MY_PKGS'`


nixmy profile
-------------

Create/rebuild Nix profile from `~/.nixpkgs/config.nix` to `$NIX_USER_PROFILE_DIR/<profilename>`

Example usage:

Lets say you have inside `~/.nixpkgs/config.nix` something like this:

    {
      packageOverrides = pkgs:
      rec {
        dockerenv = pkgs.buildEnv {
          name = "dockerenv";
          paths = [ pkgs.bash pkgs.coreutils
            pkgs.pythonPackages.fig pkgs.docker pkgs.which ];
        };
      };
    }

Then create the profile by running:

    nixmy profile dockerenv

This will build the profile and make a symlink to `$NIX_USER_PROFILE_DIR/dockerenv`

Well to use it you will need one more step, create new file with this content or something in the lines of that, depends for what do you want to use it - python environment will need much more exported variables:

    #!/bin/sh
    NIX_USER_PROFILE_DIR=/nix/var/nix/profiles/per-user/matej
    nixprofile=$NIX_USER_PROFILE_DIR/dockerenv
    export PATH="$nixprofile/bin"
    export PKG_CONFIG_PATH="$nixprofile/lib/pkgconfig"
    export PYTHONPATH="$nixprofile/lib/python2.7/site-packages"
    export PS1="dockerenv $PS1"
    #export DOCKER_HOST="tcp://127.0.0.1:9990"
    "$@"

Then make it executable and run it like:

    ./dockerenv docker ps

You might want to take a look at [this blog post](http://blog.matejc.com/blogs/myblog/control-your-packages-with-nix-environments/)


nixmy revision
--------------

 - `nixmy revision` - return the git revision for unstable channel (`nixmy update` uses this to rebase to `local` branch)
 - `nixmy revision-14` - return git revision for stable 14.12


nixmy log
---------

`git log` the [brodul's](https://github.com/brodul) way, very useful when cherry-picking.


Modifications
-------------

Feel free to modify the script.

The most common modification is to rename `nixmy revision-14` to `nixmy revision` (and remove the other one) so that you have local branch set to stable version 14.*

You might want to do this before running `nixmy init`.
