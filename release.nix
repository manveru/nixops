{ nixpkgs ? <nixpkgs>
, src ? nixopsSrc
, nixopsSrc ? { outPath = ./.; revCount = 0; shortRev = "abcdef"; rev = "HEAD"; }
, officialRelease ? false
, p ? (p: [ ])
}:

let
  pkgs = import nixpkgs { config = {}; overlays = []; };

in rec {
  nixops = pkgs.lib.genAttrs [ "x86_64-linux" "i686-linux" "x86_64-darwin" ] (system:
    let
      pkgs = import nixpkgs { inherit system; };
      nixops = import ./default.nix { inherit pkgs; };
    in nixops);
}
