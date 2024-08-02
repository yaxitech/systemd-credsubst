use std::fs::{File, OpenOptions};
use std::io::prelude::*;
use std::os::unix::fs::OpenOptionsExt;

use assert_cmd::{crate_name, Command};
use indoc::indoc;

use anyhow::Result;

#[test]
fn basic() -> Result<()> {
    let credentials_dir = tempfile::tempdir()?;
    let mut file = File::create(credentials_dir.path().join("yaxi-license"))?;
    file.write_all(b"hunter1\n\n")?;

    let mut cmd = Command::cargo_bin(crate_name!())?;
    let assert = cmd
        .env("CREDENTIALS_DIRECTORY", credentials_dir.path())
        .write_stdin(indoc! {r#"
            {
                "wurzel": "pfropf",
                "license": "${yaxi-license}",
                "wuff": "c://msdog",
                "password": "secret-password:${/with-special-chars}"
            }
        "#})
        .assert();

    assert.success().stdout(indoc! {r#"
        {
            "wurzel": "pfropf",
            "license": "hunter1",
            "wuff": "c://msdog",
            "password": "secret-password:${/with-special-chars}"
        }
    "#});

    Ok(())
}

#[test]
fn basic_in_place() -> Result<()> {
    let credentials_dir = tempfile::tempdir()?;
    File::create(credentials_dir.path().join("yaxi-license"))?.write_all(b"OG\n\n")?;

    let work_dir = tempfile::tempdir()?;
    let input_filename = work_dir.path().join("appsettings.json");
    let output_filename = work_dir.path().join("appsettings.json");

    File::create(&input_filename)?.write_all(
        indoc! {r#"
            {
                "wurzel": "pfropf",
                "license": "${yaxi-license}",
                "wuff": "c://msdog",
                "password": "secret-password:${/with-special-chars}",
                "raw": "${text}"
            }
        "#}
        .as_bytes(),
    )?;

    Command::cargo_bin(crate_name!())?
        .env("CREDENTIALS_DIRECTORY", credentials_dir.path())
        .arg("--input")
        .arg(&input_filename)
        .arg("--output")
        .arg(&output_filename)
        .assert()
        .stdout("");

    assert_eq!(
        std::fs::read_to_string(output_filename)?,
        indoc! {r#"
            {
                "wurzel": "pfropf",
                "license": "OG",
                "wuff": "c://msdog",
                "password": "secret-password:${/with-special-chars}",
                "raw": "${text}"
            }
        "#}
    );

    Ok(())
}

#[test]
fn ignores_copy_if_no_creds_with_creds_dir() -> Result<()> {
    let credentials_dir = tempfile::tempdir()?;
    File::create(credentials_dir.path().join("yaxi-license"))?.write_all(b"OG\n\n")?;

    Command::cargo_bin(crate_name!())?
        .env("CREDENTIALS_DIRECTORY", credentials_dir.path())
        .arg("--copy-if-no-creds")
        .write_stdin("license=${yaxi-license}")
        .assert()
        .stdout("license=OG")
        .stderr("");

    Ok(())
}

#[test]
fn fails_inaccessible_cred_file() -> Result<()> {
    let credentials_dir = tempfile::tempdir()?;
    let yaxi_license_file = credentials_dir.path().join("yaxi-license");
    OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o000)
        .open(&yaxi_license_file)
        .unwrap();

    Command::cargo_bin(crate_name!())?
        .env("CREDENTIALS_DIRECTORY", credentials_dir.path())
        .write_stdin("license=${yaxi-license}")
        .assert()
        .stdout("")
        .stderr(format!(
            indoc! {r#"
            Error: Failed to open '{}' for reading

            Caused by:
                Permission denied (os error 13)
        "#},
            &yaxi_license_file.to_string_lossy()
        ));

    Ok(())
}

#[test]
fn fails_non_existing_infile() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .arg("--input")
        .arg("/file/does/not/exist")
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            error: invalid value '/file/does/not/exist' for '--input <FILE>': No such file or directory (os error 2)

            For more information, try '--help'.
        "#});

    Ok(())
}

#[test]
fn fails_inaccessible_outfile() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .arg("--copy-if-no-creds")
        .arg("--output")
        .arg("/file/does/not/exist")
        .write_stdin("wurzelpfropf")
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            Error: Failed to open '/file/does/not/exist' for writing

            Caused by:
                No such file or directory (os error 2)
        "#});

    Ok(())
}

#[test]
fn rejects_invalid_pattern() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .arg("--pattern")
        .arg(r#"wurzel(pfropf"#)
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            error: invalid value 'wurzel(pfropf' for '--pattern <PATTERN>': regex parse error:
                wurzel(pfropf
                      ^
            error: unclosed group

            For more information, try '--help'.
        "#});

    Ok(())
}

#[test]
fn rejects_valid_pattern_without_id() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .arg("--pattern")
        .arg(r#"wurzelpfropf"#)
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            error: invalid value 'wurzelpfropf' for '--pattern <PATTERN>': Does not include a named group 'id'

            For more information, try '--help'.
        "#});

    Ok(())
}

#[test]
fn fails_inaccessible_creds_dir() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .env("CREDENTIALS_DIRECTORY", "/does/not/exist")
        .write_stdin("Hi")
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            Error: The $CREDENTIALS_DIRECTORY '/does/not/exist' is inaccessible. Make sure to call systemd-credsubst directly from ExecStart=/ExecStartPre=

            Caused by:
                No such file or directory (os error 2)
        "#});

    Ok(())
}

#[test]
fn fails_no_creds_dir_set() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .write_stdin("Bye")
        .assert()
        .stdout("")
        .stderr(indoc! {r#"
            Error: $CREDENTIALS_DIRECTORY unset. Consider --copy-if-no-creds if you want to raw copy input to output

            Caused by:
                environment variable not found
        "#});

    Ok(())
}

#[test]
fn copy_if_no_creds() -> Result<()> {
    Command::cargo_bin(crate_name!())?
        .arg("--copy-if-no-creds")
        .write_stdin(indoc! {r#"
            ${wurzelpfropf}
        "#})
        .assert()
        .success()
        .stdout(indoc! {r#"
            ${wurzelpfropf}
        "#});

    Ok(())
}
