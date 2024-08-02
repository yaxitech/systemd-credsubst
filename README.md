# systemd-credsubst

[![codecov](https://codecov.io/github/yaxitech/systemd-credsubst/graph/badge.svg?token=CBIaFMVIjQ)](https://codecov.io/github/yaxitech/systemd-credsubst)

[`envsubst`](https://github.com/a8m/envsubst) for systemd credentials.

Given a systemd unit with any of the credential provisioning settings (e.g, `LoadCredential=ID` or `SetCredentialEncrypted=ID`, see systemd.exec(5)),
`systemd-credsubst` substitutes references to `${ID}` with the contents of the credential when called from `ExecStartPre=` or `ExecStart=`.

## Example

Consider a service which needs to read a configuration file `appsettings.json` in its `ExecStart=` process.
For the service to start successfully, the file also needs to contain a secret license key.
To separate the secret values from (public) configuration options, the file should not contain the license key directly.
Instead, systemd should insert the credential into the configuration file before starting the main service process, i.e., in an `ExecStartPre=` command line.

Using `systemd-credsubst`, the file `/etc/appsettings.json` may contain a reference to a systemd credential ID:

```json
{
  "license": "${license}",
  "name": "Wurzelpfropf Banking"
}
```

The following service unit `credsubst-showcase.service` uses `systemd-credsubst` to insert the secret license key provisioned through `LoadCredential=`:

```ini
[Unit]
Description=Showcase systemd-credsubst

[Service]
ExecStart=tail -f -n +1 /run/credsubst-showcase/appsettings.json
ExecStartPre=systemd-credsubst --input /etc/appsettings.json --output /run/credsubst-showcase/appsettings.json
LoadCredential=license:/run/secrets/wurzelpfropf-license.secret
DynamicUser=yes
RuntimeDirectory=credsubst-showcase
```

The secret file `/run/secrets/wurzelpfropf-license.secret` contains `my-secret-license`.
Note that `systemd-creds` strips any trailing newlines.

After running `systemd-credsubst` in `ExecStartPre=`, the file `/run/credsubst-showcase/appsettings.json` has the following contents:

```json
{
  "license": "my-secret-license",
  "name": "Wurzelpfropf Banking"
}
```

## Usage

`systemd-credsubst` (loosely) resembles the command line options of [`envsubst`](https://github.com/a8m/envsubst):

```
Substitute systemd credential references from ExecStart=/ExecStartPre= calls

Usage: systemd-credsubst [OPTIONS]

Options:
  -i, --input <FILE>       If no input file is given, read from stdin.
  -o, --output <FILE>      If no output file is given, write to stdout.
  -p, --pattern <PATTERN>  Regex pattern to replace. Must at least provide a named group 'id'. By default matches ${id}. [default: \$\{(?P<id>[^\$\{\}/]+)\}]
  -c, --copy-if-no-creds   Copy input to output if $CREDENTIALS_DIRECTORY is not set
  -h, --help               Print help
  -V, --version            Print version
```
