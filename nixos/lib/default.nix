{ lib }:
let
  inherit (lib)
    attrNames
    collect
    concatMap
    elem
    evalModules
    flip
    isAttrs
    mapAttrsRecursiveCond
    mkOption
    optionalString
    toList
    ;

  # Extend `lib.types` with `loadCredential` so that the body of
  # `collectLoadCredential` below can refer to `types.loadCredential` unchanged.
  types = lib.types // {
    loadCredential = typeValueOrSubmodule;
  };

  # A LoadCredential= path is always absolute and should point outside the Nix store.
  # An exception is LoadCredentialEncrypted= but we don't currently use that and
  # checking for a path outside the Nix store seems more valuable for now.
  typeLoadCredentialPath =
    (types.pathWith {
      absolute = true;
      inStore = false;
    })
    // {
      name = "loadCredentialPath";
    };

  typePassthru =
    values:
    (types.enum values)
    // {
      name = "passthru";
    };

  typePassthruOrLoadCredentialPath =
    passthruValues:
    (types.either (typePassthru passthruValues) typeLoadCredentialPath)
    // {
      name = "passthruOrLoadCredentialPath";
    };

  typeLoadCredentialSubmodule =
    {
      id ? null,
    }:
    types.submodule (
      { config, ... }:
      {
        _file = "lib/types.nix";
        options.id = mkOption {
          # See https://github.com/systemd/systemd/blob/a108fcb/src/basic/path-util.c#L1157
          type = types.strMatching "[^\$\{\}/]+";
          description = ''
            A short ASCII string suitable as filename in the filesystem.

            Defaults to the given `id` or the SHA-256 digest of the `path` unless `path` is `null`.
          '';
          example = "access.token";
          default =
            if id != null then
              id
            else if config.path != null then
              builtins.hashString "sha256" config.path
            else
              null;
        };
        options.path = mkOption {
          type = types.nullOr typeLoadCredentialPath;
          description = ''
            A filesystem path to load the credential from.

            If `null` (the default), `LoadCredential=` looks up the `id` in well-known directories.
          '';
          example = "/run/secrets/access.token";
          default = null;
        };
        options.loadCredential = mkOption {
          type = types.str;
          readOnly = true;
          description = ''
            Value suitable to assign to `LoadCredential=`;
          '';
          example = "wurzel-token:/run/secrets/wurzelpfropfius";
          default = config.id + optionalString (config.path != null) ":${config.path}";
        };
      }
    );

  typeValueOrSubmodule =
    {
      id ? null,
      passthru ? [ ],
    }:
    let
      # Allow giving a single value instead of a list
      passthru' = toList passthru;
      t1 =
        if passthru' != [ ] then typePassthruOrLoadCredentialPath passthru' else typeLoadCredentialPath;
      t2 = typeLoadCredentialSubmodule { inherit id; };
      t = types.either t1 t2;
    in
    t
    // {
      merge =
        loc: defs:
        let
          toSubmodule =
            path:
            let
              eval = evalModules {
                modules = [
                  {
                    options.dummy = mkOption { type = typeLoadCredentialSubmodule { inherit id; }; };
                    config.dummy = { inherit path; };
                  }
                ];
              };
              readOnlyOptsWithDefault = [ "loadCredential" ];
            in
            # We have to remove `readOnly` options with a `default` to avoid having them set twice
            removeAttrs eval.config.dummy readOnlyOptsWithDefault;
          defs' = flip map defs (
            def:
            def
            // {
              value =
                # Config uses a passthru value or the submodule
                if elem def.value passthru' || isAttrs def.value then
                  def.value
                # Config uses an unstructured raw value -> convert to submodule
                else
                  toSubmodule def.value;
            }
          );
        in
        t.merge loc defs';
    };

  collectLoadCredential =
    let
      eval = evalModules {
        modules = [
          {
            _file = "lib/collectLoadCredential.nix";
            options.dummy = mkOption {
              type = types.loadCredential { };
              default = "/dummy";
            };
          }
        ];
      };
      pred = x: isAttrs x && attrNames x == attrNames eval.config.dummy;
    in
    arg: concatMap (collect pred) (toList arg);

  mapLoadCredential =
    let
      isLoadCredential = value: collectLoadCredential value == [ value ];
    in
    f:
    mapAttrsRecursiveCond (value: !(isLoadCredential value)) (
      _name: value: if isLoadCredential value then f value else value
    );
in
{
  inherit types collectLoadCredential mapLoadCredential;
}
