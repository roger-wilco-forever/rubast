use std::collections::HashMap;
use std::io::{self, Write};

#[derive(Clone)]
pub enum Value {
    Nil,
    Integer(i64),
    String(String),
    Object(usize),
}

impl Value {
    fn into_ruby_string(self) -> String {
        match self {
            Self::Nil => String::new(),
            Self::Integer(number) => number.to_string(),
            Self::String(text) => text,
            Self::Object(_) => unreachable!("object string conversion is unsupported"),
        }
    }
}

pub struct Runtime {
    // ponytail: retain objects until runtime drop; reclaim them when long-lived allocation matters.
    objects: Vec<HashMap<&'static str, Value>>,
}

impl Runtime {
    pub fn new() -> Self {
        Self {
            objects: Vec::new(),
        }
    }

    pub fn new_object(&mut self) -> Value {
        let id = self.objects.len();
        self.objects.push(HashMap::new());
        Value::Object(id)
    }

    pub fn get_ivar(&self, receiver: &Value, name: &'static str) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("instance variables require an object");
        };
        self.objects[*id].get(name).cloned().unwrap_or(Value::Nil)
    }

    pub fn set_ivar(&mut self, receiver: &Value, name: &'static str, value: Value) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("instance variables require an object");
        };
        self.objects[*id].insert(name, value.clone());
        value
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
            Value::Integer(_) | Value::Object(_) => {
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
