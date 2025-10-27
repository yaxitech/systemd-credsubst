{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.systemd-credsubst-test;
  jsonFormat = (pkgs.formats.json { });

  configFile = jsonFormat.generate "appsettings.json" (
    pkgs.systemd-credsubst-lib.systemdCredsubstify cfg.settings
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
        options.maybeASecret = pkgs.systemd-credsubst-lib.mkLoadCredentialOption {
          description = "Maybe a secret, unless assigned `kartoffelpuffer`.";
          example = "/run/secrets/maybe-a-secret";
          passthru = "kartoffelpuffer";
        };
        options.maybeADefaultSecret = pkgs.systemd-credsubst-lib.mkLoadCredentialOption rec {
          description = ''Maybe a secret, unless assigned `{ wurzel = "pfropf"; }`.'';
          example = "/run/secrets/maybe-a-secret";
          default = {
            wurzel = "pfropf";
          };
          passthru = default;
        };
        options.secretKey = pkgs.systemd-credsubst-lib.mkLoadCredentialOption {
          description = "A very secret key";
          example = "/run/secrets/a-key";
        };
        options.secretName = pkgs.systemd-credsubst-lib.mkLoadCredentialOption {
          description = "A very secret name";
          example = "/run/secrets/a-name";
          passthru = "Kaiserschmarrn";
        };
        options.secretPassword = pkgs.systemd-credsubst-lib.mkLoadCredentialOption {
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

        LoadCredential = pkgs.systemd-credsubst-lib.toLoadCredentialList cfg.settings;
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
