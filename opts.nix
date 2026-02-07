{ pkgs ? import <nixpkgs> {}, flakePath, flakeAttr }:
with pkgs.lib;
let
  flake = builtins.getFlake flakePath;

  opts = if hasSuffix ".getSubOptions" flakeAttr then
    (attrByPath (splitString "." flakeAttr) {} flake) []
  else
    attrByPath (splitString "." flakeAttr) {} flake;

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

  isValidOption = v:
    v ? _type && v._type == "option";
in
  map (v: {
    name = concatStringsSep "." v.loc;
    description = if v?description then v.description else "<not available>";
    type = v.type.description;
    default = getDefault v;
    declarations = v.declarations;
  }) (collect isValidOption opts)
