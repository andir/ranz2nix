let
  ranz2nix = import ./default.nix;
  pkgs = import ./nix;
in
rec {
  tests = {
    simple = ranz2nix { sourcePath = ./examples/simple; };
    complexer = ranz2nix { sourcePath = ./examples/complexer; };
  };

  all = pkgs.linkFarmFromDrvs "all-tests" (pkgs.lib.flatten (pkgs.lib.attrValues (
    pkgs.lib.mapAttrs
      (_: v: pkgs.lib.attrValues v
      )
      tests
  )));
}
