use std::collections::HashMap;
use std::io::{self, Write};

#[derive(Clone, PartialEq, Eq)]
pub enum Value {
    Nil,
    Bool(bool),
    Integer(i64),
    String(String),
    Object(usize),
}

impl Value {
    fn into_integer(self) -> i128 {
        let Self::Integer(value) = self else {
            unreachable!("integer operation requires proven integer operands");
        };
        i128::from(value)
    }

    fn into_ruby_string(self) -> String {
        match self {
            Self::Nil => String::new(),
            Self::Bool(value) => value.to_string(),
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

    pub fn truthy(value: &Value) -> bool {
        !matches!(value, Value::Nil | Value::Bool(false))
    }

    pub fn unary(name: &str, value: Value) -> Value {
        if name == "!" {
            return Value::Bool(!Self::truthy(&value));
        }
        let integer = value.into_integer();
        let result = match name {
            "+@" => integer,
            "-@" => -integer,
            _ => unreachable!("unknown integer unary operation"),
        };
        Value::Integer(result.try_into().expect("analysis proves an i64 result"))
    }

    pub fn binary(name: &str, left: Value, right: Value) -> Value {
        match name {
            "==" => return Value::Bool(left == right),
            "!=" => return Value::Bool(left != right),
            _ => {}
        }
        let left = left.into_integer();
        let right = right.into_integer();
        let result = match name {
            "<" => return Value::Bool(left < right),
            "<=" => return Value::Bool(left <= right),
            ">" => return Value::Bool(left > right),
            ">=" => return Value::Bool(left >= right),
            "+" => left + right,
            "-" => left - right,
            "*" => left * right,
            "/" => {
                let quotient = left / right;
                let remainder = left % right;
                quotient - i128::from(remainder != 0 && ((remainder < 0) != (right < 0)))
            }
            "%" => {
                let remainder = left % right;
                if remainder != 0 && ((remainder < 0) != (right < 0)) {
                    remainder + right
                } else {
                    remainder
                }
            }
            _ => unreachable!("unknown integer binary operation"),
        };
        Value::Integer(result.try_into().expect("analysis proves an i64 result"))
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
            Value::Bool(_) | Value::Integer(_) | Value::Object(_) => {
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
