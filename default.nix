{ pkgs ? import ./nix
, lib ? pkgs.lib
, nodejs ? pkgs.nodejs
, nodeEnv ? pkgs.callPackage (pkgs.path + "/pkgs/development/node-packages/node-env.nix") { inherit nodejs; }
  /* required input parameters */
, sourcePath # path to the root of the sources for this node package
, lockFilePath ? sourcePath + "/package-lock.json" # path of the lock file
}:
let
  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);
  dependencies = lockFile.dependencies or { };
  mkSource = _: v: pkgs.fetchurl { url = v.resolved; hash = v.integrity; };
  sources = lib.mapAttrs (mkSource) dependencies;

  mkNode2NixDependency = previous: sourcesList: name: dep: builtins.trace [ name dep ] (
    let
      uid = "${name}-${dep.version}";
      dsources = lib.mapAttrs (mkSource) (dep.dependencies or { });
    in
    if builtins.elem uid previous then null else {
      inherit name;
      packageName = name;
      inherit (dep) version;
      src = sources.${name}; # (lib.head (lib.filter (builtins.elem name) sourcesList)).${name};
      dependencies =
        lib.filter (v: v != null && (builtins.hasAttr v.name dependencies && dependencies.${v.name}.version != v.version)) (
          let
            names = lib.attrNames (dep.requires or { });
          in
          map
            (name:
              if builtins.hasAttr name dependencies then
                mkNode2NixDependency ([ uid ] ++ previous) ([ dsources ] ++ sourcesList) name (dependencies.${name})
              else builtins.throw "Dependency ${name} not known")
            names
        );
    }
  );
  args = {
    inherit (lockFile) name version;
    packageName = lockFile.name;
    src = sourcePath;
    dependencies = lib.attrValues (lib.mapAttrs (mkNode2NixDependency [ ] [ sources ]) dependencies);
    bypassCache = true;
    production = true;
  };
in
{
  dependenciesJson = builtins.toJSON dependencies;
  inherit dependencies;
  allSources = pkgs.linkFarmFromDrvs "dependencies-for-${lockFile.name}" (lib.attrValues sources);
  shell = nodeEnv.buildNodeShell args;
  tarball = nodeEnv.buildNodeSourceDist args;
  package = nodeEnv.buildNodePackage args;
}
