{ pkgs ? import ./nix
, lib ? pkgs.lib
, nodejs ? pkgs.nodejs
, nodeEnv ? pkgs.callPackage (pkgs.path + "/pkgs/development/node-packages/node-env.nix") { inherit nodejs; }
  /* required input parameters */
, sourcePath # path to the root of the sources for this node package
, lockFilePath ? sourcePath + "/package-lock.json" # path of the lock file
, packageOverride ? name: spec: {},
}:
let
  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);
  dependencies = lockFile.dependencies or { };
  mkSource = name: v: if (v.resolved or "") == "" then null else pkgs.fetchurl { url = builtins.trace (name + " " + v.resolved) v.resolved; hash = v.integrity; };
  sources = lib.mapAttrs (mkSource) dependencies;

  findBestSource = sourcesList: name:
    let
      candidatese = lib.filter (l: builtins.hasAttr name l && builtins.trace ("'" + (l.name or "N/A") + "'") (l.${name} != "")) sourcesList;
      best = lib.head candidatese;
    in
    best.${name};

  mkNode2NixDependency = previous: sourcesList: name: dep: builtins.trace [ name dep ] (
    let
      uid = "${name}-${dep.version}";
      dsources = lib.mapAttrs (mkSource) (dep.dependencies or { });
    in
    if builtins.elem uid previous then null else {
      inherit name;
      packageName = name;
      inherit (dep) version;
      src = findBestSource sourcesList name;
      dependencies =
        lib.filter (v: v != null && (builtins.hasAttr v.name dependencies && dependencies.${v.name}.version != v.version)) (
          let
            names = lib.attrNames (dep.requires or { });
          in
          map
            (name:
              if (dep.dependencies.${name} or dependencies.${name} or null) != null then
                mkNode2NixDependency ([ uid ] ++ previous) ([ dsources ] ++ sourcesList) name (dep.dependencies.${name} or dependencies.${name})
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

  patchedLockfile = pkgs.writeTextFile {
    name = "package-lock.json";
    destination = "/package-lock.json";
    text = (
      let
        patchDep = sourcesList: name: v:
          let
            dsources = lib.mapAttrs (mkSource) (v.dependencies or { });
            src = findBestSource sourcesList name;
          in
          (v // {
            dependencies = lib.mapAttrs (patchDep ([ dsources ] ++ sourcesList)) (v.dependencies or { });
          }) // (if src == null then packageOverride name v else {
            resolved = "file://" + (toString src);
          }
          );

        file = lockFile // {
          dependencies = lib.mapAttrs (patchDep [ sources ]) (lockFile.dependencies or { });
        };
      in
      builtins.toJSON file
    );
  };

  patchedBuildRoot = pkgs.symlinkJoin {
    name = "patched-root-${lockFile.name}";
    paths = [
      patchedLockfile
      sourcePath
    ];
  };

  patchedBuild = pkgs.stdenv.mkDerivation {
    name = lockFile.name;
    src = patchedBuildRoot;
    buildInputs = [ nodejs ];

    buildPhase = ''
      export HOME=$(mktemp -d)

      chmod -R +rw .

      npm --offline install
    '';

    installPhase = ''
      ls -la
      mkdir $out
      cp -rv node_modules $out/node_modules
    '';

    passthru.lockFile = patchedLockfile + "/package-lock.json";
  };
in
{
  dependenciesJson = builtins.toJSON dependencies;
  inherit dependencies patchedLockfile patchedBuildRoot patchedBuild;
  allSources = pkgs.linkFarmFromDrvs "dependencies-for-${lockFile.name}" (lib.attrValues sources);
  shell = nodeEnv.buildNodeShell args;
  tarball = nodeEnv.buildNodeSourceDist args;
  package = nodeEnv.buildNodePackage args;
}
