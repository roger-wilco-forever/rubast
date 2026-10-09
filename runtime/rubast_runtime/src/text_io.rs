use crate::{Location, Outcome, Runtime, Value};
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};

pub(crate) mod inspection;

impl Runtime {
    pub fn checked_io(
        &mut self,
        name: &str,
        receiver: Value,
        arguments: Vec<Value>,
        location: Location,
    ) -> Outcome {
        let Value::Stream(stream) = receiver else {
            unreachable!("I/O requires a validated stream or File receiver")
        };
        let kernel = name.starts_with("kernel_");
        let name = name.strip_prefix("kernel_").unwrap_or(name);
        let label = match (stream, name, kernel) {
            (_, "gets", true) => "Kernel#gets",
            (_, "print", true) => "Kernel#print",
            (_, "puts", true) => "Kernel#puts",
            (_, "p", true) => "Kernel#p",
            ("file_class", "read", _) => "IO.read",
            ("file_class", "write", _) => "IO.write",
            (_, "read", _) => "IO#read",
            (_, "gets", _) => "IO#gets",
            (_, "write", _) => "IO#write",
            (_, "print", _) => "IO#print",
            (_, "warn", _) => "Kernel#warn",
            (_, "puts", _) => "IO#puts",
            (_, "flush", _) => "IO#flush",
            _ => unreachable!(),
        };
        let builtin =
            Location::new(location.path, location.line, label).highlight(location.highlight);
        self.enter(location);
        let result = if stream == "file_class" {
            self.file_operation(name, arguments, builtin)
        } else {
            self.stream_operation(name, stream, arguments, builtin)
        };
        self.leave();
        result
    }

    fn file_operation(&mut self, name: &str, arguments: Vec<Value>, location: Location) -> Outcome {
        let path = arguments[0].clone().into_ruby_string();
        if path.contains('\0') {
            return self.runtime_error(
                "ArgumentError",
                "path name contains null byte".into(),
                location,
            );
        }
        let opened = if name == "read" {
            File::open(&path)
        } else {
            OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&path)
        };
        let mut file = match opened {
            Ok(file) => file,
            Err(error) => return self.io_error(error, "rb_sysopen", &path, location),
        };
        if name == "read" {
            let mut bytes = Vec::new();
            return match file.read_to_end(&mut bytes) {
                Ok(_) => self.utf8_value(bytes, location),
                Err(error) => self.io_error(error, "io_fread", &path, location),
            };
        }
        let text = arguments[1].clone().into_ruby_string();
        match file.write_all(text.as_bytes()) {
            Ok(()) => Ok(Value::Integer(
                text.len().try_into().expect("text size fits i64"),
            )),
            Err(error) => {
                let operation = if text.len() < 8192 {
                    "fptr_finalize_flush"
                } else {
                    "rb_sys_fail_on_write"
                };
                self.io_error(error, operation, &path, location)
            }
        }
    }

    fn stream_operation(
        &mut self,
        name: &str,
        stream: &'static str,
        arguments: Vec<Value>,
        location: Location,
    ) -> Outcome {
        if matches!(name, "read" | "gets") {
            if stream != "stdin" {
                return self.runtime_error("IOError", "not opened for reading".into(), location);
            }
            let mut bytes = Vec::new();
            let result = if name == "gets" {
                std::io::BufRead::read_until(&mut io::stdin().lock(), b'\n', &mut bytes)
            } else {
                io::stdin().lock().read_to_end(&mut bytes)
            };
            return match result {
                Ok(0) if name == "gets" => Ok(Value::Nil),
                Ok(_) => self.utf8_value(bytes, location),
                Err(error) => self.io_error(error, "io_fread", "<STDIN>", location),
            };
        }
        if name == "flush" {
            let result = match stream {
                "stdout" => io::stdout().flush(),
                "stderr" => io::stderr().flush(),
                _ => Ok(()),
            };
            return match result {
                Ok(()) => Ok(Value::Stream(stream)),
                Err(error) => self.io_error(error, "rb_io_flush_raw", stream, location),
            };
        }
        if stream == "stdin" {
            if name == "write" {
                return self.runtime_error("IOError", "not opened for writing".into(), location);
            }
            let inner = Location::new(location.path, location.line, "IO#write");
            self.enter(location);
            let result = self.runtime_error("IOError", "not opened for writing".into(), inner);
            self.leave();
            return result;
        }
        let mut text = String::new();
        if name == "puts" && arguments.is_empty() {
            text.push('\n');
        }
        for value in arguments {
            let part = if name == "p" {
                inspection::inspect(value)
            } else {
                value.into_ruby_string()
            };
            text.push_str(&part);
            if matches!(name, "puts" | "warn" | "p") && !part.ends_with('\n') {
                text.push('\n');
            }
        }
        let result = if stream == "stdout" {
            io::stdout()
                .lock()
                .write_all(text.as_bytes())
                .and_then(|()| io::stdout().flush())
        } else {
            io::stderr()
                .lock()
                .write_all(text.as_bytes())
                .and_then(|()| io::stderr().flush())
        };
        match result {
            Ok(()) if name == "write" => Ok(Value::Integer(
                text.len().try_into().expect("text size fits i64"),
            )),
            Ok(()) => Ok(Value::Nil),
            Err(error) => self.io_error(
                error,
                "io_write",
                if stream == "stdout" {
                    "<STDOUT>"
                } else {
                    "<STDERR>"
                },
                location,
            ),
        }
    }

    fn utf8_value(&mut self, bytes: Vec<u8>, location: Location) -> Outcome {
        match String::from_utf8(bytes) {
            Ok(text) => Ok(Value::from(text)),
            // shortcut: text I/O accepts valid UTF-8 only; add byte strings before claiming other inputs.
            Err(_) => self.runtime_error(
                "Encoding::InvalidByteSequenceError",
                "input is outside the supported UTF-8 text contract".into(),
                location,
            ),
        }
    }

    fn io_error(
        &mut self,
        error: io::Error,
        operation: &str,
        path: &str,
        location: Location,
    ) -> Outcome {
        // shortcut: Linux errno values; use platform tables before supporting other operating systems.
        let class = match error.raw_os_error() {
            Some(2) => "Errno::ENOENT",
            Some(5) => "Errno::EIO",
            Some(9) => "Errno::EBADF",
            Some(13) => "Errno::EACCES",
            Some(17) => "Errno::EEXIST",
            Some(20) => "Errno::ENOTDIR",
            Some(21) => "Errno::EISDIR",
            Some(28) => "Errno::ENOSPC",
            Some(30) => "Errno::EROFS",
            Some(32) => "Errno::EPIPE",
            Some(36) => "Errno::ENAMETOOLONG",
            Some(40) => "Errno::ELOOP",
            _ => "SystemCallError",
        };
        let description = error.to_string();
        let description = description.split(" (os error").next().unwrap();
        self.runtime_error(
            class,
            format!("{description} @ {operation} - {path}"),
            location,
        )
    }
}
