use std::io::{self, Write};

#[derive(Clone)]
pub enum Value {
    Nil,
    Integer(i64),
    String(String),
    // ponytail: stateless objects need only a tag; add shared identity with instance state.
    Object,
}

impl Value {
    fn into_ruby_string(self) -> String {
        match self {
            Self::Nil => String::new(),
            Self::Integer(number) => number.to_string(),
            Self::String(text) => text,
            Self::Object => unreachable!("object string conversion is unsupported"),
        }
    }
}

pub struct Runtime;

impl Runtime {
    pub fn new() -> Self {
        Self
    }

    pub fn gets(&mut self) -> Value {
        let mut line = String::new();
        let bytes_read = io::stdin()
            .read_line(&mut line)
            .expect("failed to read standard input");

        if bytes_read == 0 {
            Value::Nil
        } else {
            Value::String(line)
        }
    }

    pub fn safe_chomp(value: Value) -> Value {
        match value {
            Value::Nil => Value::Nil,
            Value::String(mut text) => {
                let suffix_bytes = if text.ends_with("\r\n") {
                    2
                } else if text.ends_with('\n') || text.ends_with('\r') {
                    1
                } else {
                    0
                };
                text.truncate(text.len() - suffix_bytes);
                Value::String(text)
            }
            Value::Integer(_) | Value::Object => {
                unreachable!("safe_chomp requires a string or nil")
            }
        }
    }

    pub fn interpolate(parts: Vec<Value>) -> Value {
        let mut text = String::new();
        for part in parts {
            text.push_str(&part.into_ruby_string());
        }
        Value::String(text)
    }

    pub fn puts(&mut self, value: Value) {
        let text = value.into_ruby_string();
        let mut stdout = io::stdout().lock();
        stdout
            .write_all(text.as_bytes())
            .expect("failed to write standard output");
        if !text.ends_with('\n') {
            stdout
                .write_all(b"\n")
                .expect("failed to write standard output");
        }
        stdout.flush().expect("failed to flush standard output");
    }
}
