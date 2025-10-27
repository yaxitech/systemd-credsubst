{ lib }:
with lib;
let
  loadCredentialOptionMagic = "__isLoadCredentialOption";
  isLoadCredentialOption = config: isAttrs config && hasAttr loadCredentialOptionMagic config;

  hashPath = builtins.hashString "sha256";

  typePassthruOrLoadCredentialPath =
    attrs:
    with types;
    (
      if hasAttr "passthru" attrs then
        addCheck types.anything (x: x == attrs.passthru || path.check x && !hasPrefix builtins.storeDir x)
      else
        addCheck path (p: !hasPrefix builtins.storeDir p)
    )
    // {
      name = "passthruOrLoadCredentialPath";
      description = "LoadCredential= path outside of Nix store";
    };
  typeLoadCredentialSubmodule = types.submodule (
    { config, ... }:
    {
      options.id = mkOption {
        # See https://github.com/systemd/systemd/blob/a108fcb/src/basic/path-util.c#L1157
        type = with types; nullOr (strMatching "[^\$\{\}/]+");
        description = ''
          A short ASCII string suitable as filename in the filesystem.

          Defaults to the SHA-256 digest of the `path`.
        '';
        default = hashPath config.path;
      };
      options.path = mkOption {
        type = typePassthruOrLoadCredentialPath { };
        description = "A filesystem path to load the credential from.";
      };
      options.passthru = mkOption {
        type = types.anything;
        description = "If the config assigns the given value, pass it through directly rather than transforming it to a `LoadCredential=`";
        default = null;
      };
    }
  );
in
{
  # An option type for the systemd LoadCredential= setting.
  # Allows either giving only the path to a credential or an attribute set with `id` and `path`.
  # If only a path is given, `id` is set to the SHA-256 digest of `path`.
  # If the configuration assigns a value which matches the submodule's `passthru` attribute value,
  # no credential substitution is performed.
  mkLoadCredentialOption =
    attrs:
    mkOption (
      {
        type = types.either (typePassthruOrLoadCredentialPath attrs) typeLoadCredentialSubmodule;
        apply =
          x:
          if (isAttrs x && hasAttr "id" x && hasAttr "path" x) then
            x // { ${loadCredentialOptionMagic} = true; }
          else if hasAttr "passthru" attrs && x == attrs.passthru then
            x
          else
            {
              id = hashPath x;
              path = x;
              ${loadCredentialOptionMagic} = true;
            };
      }
      // (removeAttrs attrs [ "passthru" ])
    );
  # Transform config values containing a load credential option to the pattern expected by `systemd-credsubst`
  systemdCredsubstify = mapAttrsRecursiveCond (x: !isLoadCredentialOption x) (
    _path: value: if isLoadCredentialOption value then ''''${${value.id}}'' else value
  );
  # Collect all config values which stem from a load credential option into a list suitable for `LoadCredential=`
  toLoadCredentialList =
    config: map (cred: "${cred.id}:${cred.path}") (collect isLoadCredentialOption config);
}
