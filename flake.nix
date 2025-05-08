{
  description = "envsubst for systemd credentials";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs = { self, rust-overlay, nixpkgs, crane, flake-utils, advisory-db, ... }:
    let
      lib = nixpkgs.lib;
      recursiveMerge = with lib; foldl recursiveUpdate { };
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [
          rust-overlay.overlays.default
          (final: prev: {
            craneLib = (crane.mkLib prev).overrideToolchain (final.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml);
          })
        ];
      };
    in
    recursiveMerge [
      (flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = pkgsFor system;

          craneLib = pkgs.craneLib;

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              ./deny.toml
              ./src
              ./tests
            ];
          };

          # Common arguments can be set here to avoid repeating them later
          commonArgs = {
            inherit src;
            strictDeps = true;
          };

          # Build *just* the cargo dependencies, so we can reuse
          # all of that work (e.g. via cachix) when running in CI
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          packages.systemd-credsubst = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
            doCheck = false;
            meta.mainProgram = "systemd-credsubst";
            passthru = {
              inherit cargoArtifacts commonArgs;
              inherit (self) lib;
            };
          });

          packages.default = self.packages.${system}.systemd-credsubst;

          packages.install = pkgs.${if pkgs.stdenv.isLinux then "pkgsStatic" else "pkgs"}.callPackage
            (
              { uutils-coreutils, rustPlatform }:
              rustPlatform.buildRustPackage (finalAttrs: {
                inherit (uutils-coreutils) version src doCheck;
                pname = "install";
                cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";
                cargoBuildFlags = "-p uu_${finalAttrs.pname}";
                meta.mainProgram = finalAttrs.pname;
              })
            )
            { };

          checks = {
            packages = pkgs.linkFarmFromDrvs "build-all-packages" (lib.attrValues self.packages.${system});

            # Run clippy (and deny all warnings) on the crate source,
            # again, reusing the dependency artifacts from above.
            #
            # Note that this is done as a separate derivation so that
            # we can block the CI if there are issues here, but not
            # prevent downstream consumers from building our crate by itself.
            systemd-credsubst-clippy = craneLib.cargoClippy (commonArgs // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

            systemd-credsubst-doc = craneLib.cargoDoc (commonArgs // {
              inherit cargoArtifacts;
            });

            # Check formatting
            systemd-credsubst-fmt = craneLib.cargoFmt {
              inherit src;
            };

            # Audit dependencies
            systemd-credsubst-audit = craneLib.cargoAudit {
              inherit src advisory-db;
            };

            # Audit licenses
            systemd-credsubst-deny = craneLib.cargoDeny {
              inherit src;
            };

            # Run tests with cargo-nextest and, on Linux, with coverage for Codecov
            systemd-credsubst-nextest = craneLib.cargoNextest (commonArgs // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            } // lib.optionalAttrs pkgs.stdenv.isLinux {
              withLlvmCov = true;
              cargoLlvmCovExtraArgs = ''--codecov --output-path "$out/codecov.json"'';
            });
          };

          apps.systemd-credsubst = flake-utils.lib.mkApp {
            drv = self.packages.${system}.systemd-credsubst;
          };
          apps.default = self.apps.${system}.systemd-credsubst;

          devShells.default = craneLib.devShell {
            # Inherit inputs from checks.
            checks = self.checks.${system};
          };
        }))

      #
      # LINUX OUTPUTS
      #
      (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
        let pkgs = pkgsFor system; in {
          packages.systemd-credsubst-static = self.packages.${system}.systemd-credsubst.overrideAttrs (_: {
            CARGO_BUILD_TARGET = pkgs.pkgsStatic.stdenv.targetPlatform.rust.cargoShortTarget;
          });

          packages.default = self.packages.${system}.systemd-credsubst-static;

          checks.systemd-credsubst-nixos-test = pkgs.callPackage ./nixos/tests/nixos-test-systemd-credsubst.nix {
            systemd-credsubst = self.packages.${system}.default;
          };

          checks.systemd-credsubst-nixos-test-mk-load-credential-option = pkgs.callPackage ./nixos/tests/nixos-test-mk-load-credential-option {
            systemdCredsubstOverlay = self.overlays.default;
          };
        }
      ))

      {
        lib = import ./nixos/lib { inherit (nixpkgs) lib; };
      }

      #
      # SYSTEM-INDEPENDENT OUTPUTS
      #
      {
        overlays.default = final: _prev: {
          systemd-credsubst = self.packages.${final.system}.default;
        };
      }
    ];
}
