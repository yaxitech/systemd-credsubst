{
  nixosTest,
  # args
  systemdCredsubstOverlay,
}:
nixosTest {
  name = "systemd-credsubst-test";

  nodes.machine = {
    imports = [
      { nixpkgs.overlays = [ systemdCredsubstOverlay ]; }
      ./module-systemd-credsubst-test.nix
    ];

    services.systemd-credsubst-test = {
      enable = true;
      settings = {
        environment = "Production";
        secretKey = "/run/secrets/a-key";
        secretName.path = "/run/secrets/a-name";
        secretPassword = {
          id = "secret-password";
          path = "/run/secrets/a-password";
        };
        maybeASecret = "kartoffelpuffer";
      };
    };

    # Create a secret file only accessible by root
    system.activationScripts."systemd-credsubst-test-secrets".text = ''
      mkdir --mode 700 -p /run/secrets
      echo "CLqLt9zrR5k92TqVgIUSNu+gV4pyCuNu8F9X3pEfA28=" > /run/secrets/a-key
      echo "wurzelpfropf" > /run/secrets/a-name
      echo -en "prome\ntheus\n\n" > /run/secrets/a-password
    '';
  };

  testScript = ''
    import json

    machine.start()
    machine.wait_for_unit("systemd-credsubst-test.service");

    with subtest("substitution works"):
      out = machine.succeed("cat /run/systemd-credsubst-test/workdir/appsettings.json")
      actual = json.loads(out)
      expected = {
        "environment": "Production",
        "maybeADefaultSecret": {
          "wurzel": "pfropf"
        },
        "maybeASecret": "kartoffelpuffer",
        "secretKey": "CLqLt9zrR5k92TqVgIUSNu+gV4pyCuNu8F9X3pEfA28=",
        "secretName": "wurzelpfropf",
        "secretPassword": "prome\ntheus"
      }
      assert actual == expected, f"appsettings.json has unexpected content '{out}'"

    with subtest("sets LoadCredential= ID"):
      out = machine.succeed("systemctl cat systemd-credsubst-test.service")
      assert "LoadCredential=21e6346f7782c16114b4369f84525e53152450a1bc730196d52b63953645278f:/run/secrets/a-key" in out
      assert "LoadCredential=73b7f43eb8dc4f75baa5aa1f7e605f3a9438e6278600fee34631541edf14cb80:/run/secrets/a-name" in out
      assert "LoadCredential=secret-password:/run/secrets/a-password"

      print(out)
  '';
}
