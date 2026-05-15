{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (pkgs.systemd-credsubst-lib) collectLoadCredential mapLoadCredential;

  cfg = config.services.systemd-credsubst-test;
  jsonFormat = pkgs.formats.json { };

  configFile = jsonFormat.generate "appsettings.json" (
    mapLoadCredential (cred: "\${${cred.id}}") cfg.settings
  );
in
{
  options.services.systemd-credsubst-test = {
    enable = mkEnableOption "the `systemd-credsubst` test service";
    settings = mkOption {
      type = types.submodule {
        freeformType = jsonFormat.type;
        options.environment = mkOption {
          type = types.str;
        };
        options.maybeASecret = mkOption {
          type = pkgs.systemd-credsubst-lib.types.loadCredential {
            passthru = "kartoffelpuffer";
          };
          description = "Maybe a secret, unless assigned `kartoffelpuffer`.";
          example = "/run/secrets/maybe-a-secret";
        };
        options.maybeADefaultSecret = mkOption {
          type = pkgs.systemd-credsubst-lib.types.loadCredential {
            passthru = {
              wurzel = "pfropf";
            };
          };
          description = ''Maybe a secret, unless assigned `{ wurzel = "pfropf"; }`.'';
          example = "/run/secrets/maybe-a-secret";
          default = {
            wurzel = "pfropf";
          };
        };
        options.secretKey = mkOption {
          type = pkgs.systemd-credsubst-lib.types.loadCredential { };
          description = "A very secret key";
          example = "/run/secrets/a-key";
        };
        options.secretName = mkOption {
          type = pkgs.systemd-credsubst-lib.types.loadCredential {
            passthru = "Kaiserschmarrn";
          };
          description = "A very secret name";
          example = "/run/secrets/a-name";
        };
        options.secretPassword = mkOption {
          type = pkgs.systemd-credsubst-lib.types.loadCredential { };
          description = "A very secret password";
          example = "/run/secrets/a-password";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.systemd-credsubst-test = {
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;

        LoadCredential = map (cred: cred.loadCredential) (collectLoadCredential cfg.settings);
        ExecStartPre = [
          "${pkgs.systemd-credsubst}/bin/systemd-credsubst --escape-newlines -i ${configFile} -o appsettings.json"
        ];
        ExecStart = "${pkgs.pkgsStatic.busybox}/bin/tail -f -n +1 appsettings.json";

        WorkingDirectory = "/run/systemd-credsubst-test/workdir";

        # chroot
        RuntimeDirectory = [
          "systemd-credsubst-test/workdir"
          "systemd-credsubst-test/root"
        ];
        RootDirectory = [ "/run/systemd-credsubst-test/root" ];
        BindReadOnlyPaths = [
          configFile
          pkgs.pkgsStatic.busybox.out
          pkgs.systemd-credsubst
        ];
      };
    };
  };
}
