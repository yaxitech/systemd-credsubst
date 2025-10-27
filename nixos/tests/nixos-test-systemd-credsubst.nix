{
  lib,
  nixosTest,
  systemd-credsubst,
  pkgsStatic,
}:
# Test if `systemd-credsubst` successfully substitutes `LoadCredential=` references
nixosTest {
  name = "systemd-credsubst-test";

  nodes.machine =
    let
      appsettings =
        with builtins;
        toFile "appsettings.json" (toJSON {
          "license" = ''''${license}'';
          "name" = "Wurzelpfropf Banking";
        });
    in
    {
      # Create a secret file only accessible by root
      system.activationScripts."wurzelpfropf-license".text = ''
        mkdir --mode 700 -p /run/secrets
        echo -en "prometheus\n\n" > /run/secrets/wurzelpfropf-license.secret
      '';

      systemd.services.systemd-credsubst-test = {
        enable = true;
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          DynamicUser = true;

          LoadCredential = "license:/run/secrets/wurzelpfropf-license.secret";
          ExecStartPre = [
            "${systemd-credsubst}/bin/systemd-credsubst -i ${appsettings} -o appsettings.json"
          ];
          ExecStart = "${pkgsStatic.busybox}/bin/tail -f -n +1 appsettings.json";

          WorkingDirectory = "/run/systemd-credsubst-test/workdir";

          # chroot
          RuntimeDirectory = [
            "systemd-credsubst-test/workdir"
            "systemd-credsubst-test/root"
          ];
          RootDirectory = [ "/run/systemd-credsubst-test/root" ];
          BindReadOnlyPaths = [
            appsettings
            pkgsStatic.busybox.out
            systemd-credsubst
          ];
        };
      };

      specialisation."passthru-parents".configuration = {
        systemd.services.systemd-credsubst-test.serviceConfig = {
          ExecStart = lib.mkForce "${pkgsStatic.busybox}/bin/tail -f -n +1 some/dir/appsettings.json";
          ExecStartPre = lib.mkForce [
            "${systemd-credsubst}/bin/systemd-credsubst -c -i ${appsettings} -m -o some/dir/appsettings.json"
          ];
          LoadCredential = lib.mkForce [ ];
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      machine.start()
      machine.wait_for_unit("systemd-credsubst-test.service");

      with subtest("substitution works"):
        out = machine.succeed("cat /run/systemd-credsubst-test/workdir/appsettings.json")
        assert out == '{"license":"prometheus","name":"Wurzelpfropf Banking"}', f"appsettings.json has unexpected content '{out}'"

      with subtest("passthru and make parents works"):
        machine.succeed("${nodes.machine.system.build.toplevel}/specialisation/passthru-parents/bin/switch-to-configuration test")
        machine.wait_for_unit("systemd-credsubst-test.service");
        out = machine.succeed("cat /run/systemd-credsubst-test/workdir/some/dir/appsettings.json")
        assert out == '{"license":"''${license}","name":"Wurzelpfropf Banking"}', f"appsettings.json has unexpected content '{out}'"
    '';
}
