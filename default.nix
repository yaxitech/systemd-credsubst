{
  lib,
  rustPlatform,
}:
let
  cargoToml = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = cargoToml.package.name;
  version = cargoToml.package.version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  meta.mainProgram = finalAttrs.pname;
})
