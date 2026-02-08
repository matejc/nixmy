{ pkgs ? import <nixpkgs> { config.home-manager.users."<name>".home.stateVersion = "1"; }, flakePath ? builtins.getEnv "PWD", attr ? null }:
with pkgs.lib;
let
  flake = builtins.getFlake flakePath;

  hasSubOptions = hasSuffix ".getSubOptions" attr;

  opts = if hasSubOptions then
    ((attrByPath (splitString "." attr) {} flake) [])
  else
    attrByPath (splitString "." attr) {} flake;

  previewNix = parent: name:
    let
      eval = builtins.tryEval (_previewNix (attrByPath [name] "<error>" parent) [] []);
    in
      if eval.success then
        eval.value
      else
        "<error>";

  _previewNix = value: npath: list:
    if any (i: concatStringsSep "." npath == i) list then
      "<recursive>"
    else if isNull value then
      "<null>"
    else if builtins.isFunction value then
      "<function>"
    else if builtins.isList value then
      imap0 (i: v: _previewNix v (npath++[(toString i)]) (list++[(concatStringsSep "." (npath++[(toString i)]))])) value
    else if builtins.isAttrs value then
      mapAttrs (n: v: _previewNix v (npath++[n]) (list++[(concatStringsSep "." (npath++[n]))])) value
    else
      toString value;

  getDefault = v:
    if v?defaultText && v.defaultText?text then
      "<${v.defaultText.text}>"
    else if v?defaultText then
      v.defaultText
    else if v?default then
      previewNix v "default"
    else "<not available>";

  getExample = v:
    if v?example && v.example?text then
      previewNix v.example "text"
    else if v?example then
      previewNix v "example"
    else "<not available>";

  throws = path: attrs:
    let
      eval = builtins.tryEval (attrByPath path {} attrs);
    in
      !eval.success;

  isValidOption = v:
    v ? _type && v._type == "option";

  getOpt = v:
    {
      name = concatStringsSep "." (if hasSubOptions then drop 1 v.loc else v.loc);
      description = if v?description then v.description else "<not available>";
      type = v.type.description;
      default = getDefault v;
      example = getExample v;
      declarations = if v?declarations then v.declarations else [];
    };

  filterUnthrowableRecursive =
    set:
    let
      recurse =
        path:
        mapAttrs (
          name: value:
          if !throws (path ++ [ name ]) set then
            if isAttrs value then
              recurse (path ++ [ name ]) value
            else
              value
          else
            "<error>"
        );
    in
    recurse [ ] set;
in
  map getOpt ((collect isValidOption) (filterUnthrowableRecursive opts))
