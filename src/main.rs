use anyhow::{Context, Result};
use clap::{crate_name, Parser};
use regex::Regex;
use std::env;
use std::fs::File;
use std::process::ExitCode;
use std::{
    collections::HashMap,
    fs, io,
    io::{BufReader, Read, Write},
    path::{Path, PathBuf},
};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[arg(
        short,
        long,
        value_name = "FILE",
        value_parser = validate_path_exists,
        help = "If no input file is given, read from stdin."
    )]
    input: Option<PathBuf>,
    #[arg(
        short,
        long,
        value_name = "FILE",
        help = "If no output file is given, write to stdout."
    )]
    output: Option<PathBuf>,
    #[arg(
        short,
        long,
        // See https://github.com/systemd/systemd/blob/a108fcb/src/basic/path-util.c#L1157
        default_value = r#"\$\{(?P<id>[^\$\{\}/]+)\}"#,
        value_parser = parse_pattern,
        help = "Regex pattern to replace. Must at least provide a named group 'id'. By default matches ${id}.",
    )]
    pattern: Regex,
    #[arg(
        short,
        long,
        help = "Copy input to output if $CREDENTIALS_DIRECTORY is not set."
    )]
    copy_if_no_creds: bool,
    #[arg(
        short,
        long,
        help = "Make parent directories of the output file as needed."
    )]
    make_parents: bool,
    #[arg(short, long, help = "Escape newlines.")]
    escape_newlines: bool,
}

fn validate_path_exists(path: &str) -> Result<PathBuf, String> {
    match fs::metadata(path) {
        Ok(_) => Ok(PathBuf::from(path)),
        Err(e) => Err(e.to_string()),
    }
}

fn parse_pattern(pattern: &str) -> Result<Regex, String> {
    let re = match Regex::new(pattern) {
        Ok(re) => re,
        Err(e) => return Err(e.to_string()),
    };

    if !pattern.contains("(?P<id>") {
        return Err(String::from("Does not include a named group 'id'"));
    }

    Ok(re)
}

fn list_files(path: &str) -> Result<HashMap<String, String>> {
    let mut files = HashMap::new();

    let path = Path::new(&path);
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        if let Some(file_name) = entry.file_name().to_str() {
            let full_path = entry.path().display().to_string();
            files.insert(file_name.to_string(), full_path);
        }
    }

    Ok(files)
}

fn input_reader(input: Option<&PathBuf>) -> Result<Box<dyn Read>> {
    let reader: Box<dyn Read> = match input {
        None => Box::new(BufReader::new(io::stdin())),
        Some(filename) => {
            let f = File::open(filename).context(format!(
                "Failed to open '{}' for reading",
                filename.display()
            ))?;
            Box::new(BufReader::new(f))
        }
    };
    Ok(reader)
}

fn output_writer(output: Option<&PathBuf>, make_parents: bool) -> Result<Box<dyn Write>> {
    let writer: Box<dyn Write> = match output {
        None => Box::new(io::stdout()) as Box<dyn Write>,
        Some(filename) => {
            if make_parents {
                let parent_dir = &filename.parent().unwrap_or(Path::new("/"));
                fs::create_dir_all(parent_dir).context(format!(
                    "Failed to create parent directories of '{}'",
                    filename.display()
                ))?;
            }
            let f = File::create(filename).context(format!(
                "Failed to open '{}' for writing",
                filename.display()
            ))?;
            Box::new(f) as Box<dyn Write>
        }
    };
    Ok(writer)
}

fn passthru(input: Option<&PathBuf>, output: Option<&PathBuf>, make_parents: bool) -> Result<()> {
    let mut reader = input_reader(input)?;
    let mut writer = output_writer(output, make_parents)?;

    io::copy(&mut reader, &mut writer)?;

    Ok(())
}

// https://docs.rs/regex/1.10.5/regex/struct.Regex.html#fallibility
fn replace_all(
    re: &Regex,
    haystack: &str,
    replacement: impl Fn(&regex::Captures) -> Result<String>,
) -> Result<String> {
    let mut new = String::with_capacity(haystack.len());
    let mut last_match = 0;
    for caps in re.captures_iter(haystack) {
        let m = caps.get(0).unwrap();
        new.push_str(&haystack[last_match..m.start()]);
        new.push_str(&replacement(&caps)?);
        last_match = m.end();
    }
    new.push_str(&haystack[last_match..]);
    Ok(new)
}

fn substitute(
    input: Option<&PathBuf>,
    output: Option<&PathBuf>,
    creds_dir: &str,
    pattern: &Regex,
    make_parents: bool,
    escape_newlines: bool,
) -> Result<()> {
    // Read input as string
    let mut reader = input_reader(input)?;
    let mut contents = String::new();
    reader
        .read_to_string(&mut contents)
        .context("Failed to read given input")?;

    // Get a dictionary of credentials ids and their file path
    let creds = list_files(creds_dir).context("Failed to list files in $CREDENTIALS_DIRECTORY")?;

    // Replace all references to credentials with the the content of the file they reference
    let modified = replace_all(
        pattern,
        &contents,
        |caps: &regex::Captures| -> Result<String> {
            let id: &str = caps
                .name("id")
                .context("Pattern should always have named group 'id'")
                .map(|m| m.as_str())?;

            creds.get(id).map_or_else(
                || Ok(caps[0].to_string()),
                |secret_path| {
                    fs::read_to_string(secret_path)
                        .context(format!("Failed to open '{secret_path}' for reading"))
                        .map(|s| s.trim_end().to_string())
                        .map(|s| {
                            if escape_newlines {
                                s.replace("\n", "\\n")
                            } else {
                                s
                            }
                        })
                },
            )
        },
    )?;

    // Write the modified contents
    let mut writer = output_writer(output, make_parents)?;
    writer.write_all(modified.as_bytes())?;

    Ok(())
}

fn main() -> Result<ExitCode> {
    let cli = Cli::parse();

    let creds_dir = env::var("CREDENTIALS_DIRECTORY")
        .context("$CREDENTIALS_DIRECTORY unset. Consider --copy-if-no-creds if you want to raw copy input to output")
        .map(|dir| {
            fs::metadata(&dir)
                .context(format!("The $CREDENTIALS_DIRECTORY '{}' is inaccessible. Make sure to call {} directly from ExecStart=/ExecStartPre=", &dir, crate_name!()))
                .map(|_| dir)
        });

    match creds_dir {
        Ok(creds_dir) => substitute(
            cli.input.as_ref(),
            cli.output.as_ref(),
            &creds_dir?,
            &cli.pattern,
            cli.make_parents,
            cli.escape_newlines,
        )?,
        Err(err) => {
            if cli.copy_if_no_creds {
                passthru(cli.input.as_ref(), cli.output.as_ref(), cli.make_parents)?;
            } else {
                return Err(err);
            }
        }
    }

    Ok(ExitCode::SUCCESS)
}
