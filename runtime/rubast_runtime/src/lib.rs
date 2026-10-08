use std::cell::RefCell;
use std::collections::HashMap;
use std::io::{self, Write};
use std::ops::Deref;
use std::rc::Rc;

mod exceptions;
use exceptions::ErrorRef;
pub use exceptions::{Flow, Location, Outcome};

#[derive(Debug)]
pub struct RubyString {
    text: RefCell<String>,
    frozen: Option<&'static str>,
}
impl Deref for RubyString {
    type Target = RefCell<String>;
    fn deref(&self) -> &Self::Target {
        &self.text
    }
}
impl PartialEq for RubyString {
    fn eq(&self, other: &Self) -> bool {
        *self.borrow() == *other.borrow()
    }
}
impl Eq for RubyString {}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Value {
    Nil,
    Bool(bool),
    Integer(i64),
    Symbol(&'static str),
    String(Rc<RubyString>),
    Exception(ErrorRef),
    Object(usize),
}

impl Value {
    pub fn frozen(text: String, inspected: &'static str) -> Self {
        Self::String(Rc::new(RubyString {
            text: RefCell::new(text),
            frozen: Some(inspected),
        }))
    }

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
            Self::Symbol(name) => name.to_owned(),
            Self::String(text) => text.borrow().clone(),
            Self::Exception(error) => error.borrow().message.clone().into_ruby_string(),
            Self::Object(_) => unreachable!("object string conversion is unsupported"),
        }
    }
}

impl From<String> for Value {
    fn from(text: String) -> Self {
        Self::String(Rc::new(RubyString {
            text: RefCell::new(text),
            frozen: None,
        }))
    }
}

enum Object {
    Instance(HashMap<&'static str, Value>),
    Array(Vec<Value>),
    Hash(Vec<(Value, Value)>),
}

pub struct Runtime {
    // ponytail: retain objects until runtime drop; reclaim them when long-lived allocation matters.
    objects: Vec<Object>,
    frames: Vec<Location>,
    exceptions: Vec<ErrorRef>,
}

impl Runtime {
    pub fn new() -> Self {
        Self {
            objects: Vec::new(),
            frames: Vec::new(),
            exceptions: Vec::new(),
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

    pub fn checked_binary(
        &mut self,
        name: &str,
        left: Value,
        right: Value,
        location: Location,
    ) -> Outcome {
        if matches!(name, "/" | "%") && matches!(right, Value::Integer(0)) {
            let builtin = Location::new(
                location.path,
                location.line,
                if name == "/" {
                    "Integer#/"
                } else {
                    "Integer#%"
                },
            );
            self.enter(location);
            let result =
                self.runtime_error("ZeroDivisionError", "divided by 0".to_owned(), builtin);
            self.leave();
            return result;
        }
        Ok(Self::binary(name, left, right))
    }

    pub fn checked_array(
        &mut self,
        name: &str,
        receiver: Value,
        arguments: Vec<Value>,
        location: Location,
    ) -> Outcome {
        if name == "[]=" {
            let Value::Object(id) = receiver else {
                unreachable!()
            };
            let Object::Array(values) = &self.objects[id] else {
                unreachable!()
            };
            let Value::Integer(index) = arguments[0] else {
                unreachable!()
            };
            if i128::from(index) < -(values.len() as i128) {
                let message = format!(
                    "index {} too small for array; minimum: {}",
                    index,
                    -(values.len() as i128)
                );
                return self.runtime_error("IndexError", message, location);
            }
        }
        Ok(self.array_operation(name, receiver, arguments))
    }

    pub fn checked_string(
        &mut self,
        name: &str,
        receiver: Value,
        arguments: Vec<Value>,
        location: Location,
    ) -> Outcome {
        let Value::String(text) = &receiver else {
            unreachable!()
        };
        if text.frozen.is_some() && matches!(name, "<<" | "concat" | "replace" | "clear" | "chomp!")
        {
            let message = format!("can't modify frozen String: {}", text.frozen.unwrap());
            if name != "<<" {
                let label = match name {
                    "concat" => "String#concat",
                    "replace" => "String#replace",
                    "clear" => "String#clear",
                    "chomp!" => "String#chomp!",
                    _ => unreachable!(),
                };
                let builtin = Location::new(location.path, location.line, label);
                self.enter(location);
                let result = self.runtime_error("FrozenError", message, builtin);
                self.leave();
                return result;
            }
            return self.runtime_error("FrozenError", message, location);
        }
        Ok(Self::string_operation(name, receiver, arguments))
    }

    pub fn new_object(&mut self) -> Value {
        let id = self.objects.len();
        self.objects.push(Object::Instance(HashMap::new()));
        Value::Object(id)
    }

    pub fn new_array(&mut self, values: Vec<Value>) -> Value {
        let id = self.objects.len();
        self.objects.push(Object::Array(values));
        Value::Object(id)
    }

    pub fn array_operation(
        &mut self,
        name: &str,
        receiver: Value,
        mut arguments: Vec<Value>,
    ) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("array operations require a proven array receiver");
        };
        let Object::Array(values) = &mut self.objects[id] else {
            unreachable!("array operations require array storage");
        };
        match name {
            "length" => Value::Integer(values.len().try_into().expect("array length fits i64")),
            "!" => Value::Bool(false),
            "push" | "<<" => {
                values.extend(arguments);
                Value::Object(id)
            }
            "[]" | "[]=" => {
                let index = arguments.remove(0).into_integer();
                let index = if index < 0 {
                    values.len() as i128 + index
                } else {
                    index
                };
                if name == "[]" {
                    usize::try_from(index)
                        .ok()
                        .and_then(|slot| values.get(slot))
                        .cloned()
                        .unwrap_or(Value::Nil)
                } else {
                    let index = usize::try_from(index)
                        .expect("analysis proves a nonnegative bounded write index");
                    let value = arguments.remove(0);
                    if index >= values.len() {
                        values.resize(index + 1, Value::Nil);
                    }
                    values[index] = value.clone();
                    value
                }
            }
            _ => unreachable!("unknown array operation"),
        }
    }

    pub fn new_hash(&mut self, pairs: Vec<(Value, Value)>) -> Value {
        let id = self.objects.len();
        self.objects.push(Object::Hash(Vec::new()));
        let receiver = Value::Object(id);
        for (key, value) in pairs {
            self.hash_operation("[]=", receiver.clone(), vec![key, value]);
        }
        receiver
    }

    pub fn hash_operation(
        &mut self,
        name: &str,
        receiver: Value,
        mut arguments: Vec<Value>,
    ) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("hash operations require a proven hash receiver");
        };
        let Object::Hash(entries) = &mut self.objects[id] else {
            unreachable!("hash operations require hash storage");
        };
        match name {
            "length" => Value::Integer(entries.len().try_into().expect("hash length fits i64")),
            "!" => Value::Bool(false),
            "keys" | "values" => {
                let values = entries
                    .iter()
                    .map(|(key, value)| {
                        if name == "keys" {
                            key.clone()
                        } else {
                            value.clone()
                        }
                    })
                    .collect();
                self.new_array(values)
            }
            "[]" | "[]=" | "key?" => {
                let key = arguments.remove(0);
                // ponytail: linear lookup preserves insertion order; use an ordered map if large hashes matter.
                let slot = entries.iter().position(|(existing, _)| existing == &key);
                match name {
                    "key?" => Value::Bool(slot.is_some()),
                    "[]" => slot
                        .map(|index| entries[index].1.clone())
                        .unwrap_or(Value::Nil),
                    _ => {
                        let value = arguments.remove(0);
                        if let Some(index) = slot {
                            entries[index].1 = value.clone();
                        } else {
                            entries.push((key, value.clone()));
                        }
                        value
                    }
                }
            }
            _ => unreachable!("unknown hash operation"),
        }
    }

    pub fn get_ivar(&self, receiver: &Value, name: &'static str) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("instance variables require an object");
        };
        let Object::Instance(fields) = &self.objects[*id] else {
            unreachable!("instance variables require instance storage");
        };
        fields.get(name).cloned().unwrap_or(Value::Nil)
    }

    pub fn set_ivar(&mut self, receiver: &Value, name: &'static str, value: Value) -> Value {
        let Value::Object(id) = receiver else {
            unreachable!("instance variables require an object");
        };
        let Object::Instance(fields) = &mut self.objects[*id] else {
            unreachable!("instance variables require instance storage");
        };
        fields.insert(name, value.clone());
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
            Value::from(line)
        }
    }

    pub fn safe_chomp(value: Value) -> Value {
        match value {
            Value::Nil => Value::Nil,
            Value::String(text) => {
                let mut copy = text.borrow().clone();
                Self::chomp_text(&mut copy);
                Value::from(copy)
            }
            Value::Bool(_)
            | Value::Integer(_)
            | Value::Symbol(_)
            | Value::Object(_)
            | Value::Exception(_) => {
                unreachable!("safe_chomp requires a string or nil")
            }
        }
    }

    pub fn interpolate(parts: Vec<Value>) -> Value {
        let mut text = String::new();
        for part in parts {
            text.push_str(&part.into_ruby_string());
        }
        Value::from(text)
    }

    fn chomp_text(text: &mut String) -> bool {
        let suffix_bytes = if text.ends_with("\r\n") {
            2
        } else if text.ends_with('\n') || text.ends_with('\r') {
            1
        } else {
            0
        };
        text.truncate(text.len() - suffix_bytes);
        suffix_bytes != 0
    }

    pub fn string_operation(name: &str, receiver: Value, mut arguments: Vec<Value>) -> Value {
        let Value::String(text) = receiver else {
            unreachable!("string operations require a proven string receiver");
        };
        match name {
            "length" => Value::Integer(
                text.borrow()
                    .chars()
                    .count()
                    .try_into()
                    .expect("string length fits i64"),
            ),
            "bytesize" => Value::Integer(
                text.borrow()
                    .len()
                    .try_into()
                    .expect("string bytesize fits i64"),
            ),
            "dup" => Value::from(text.borrow().clone()),
            "chomp" => Self::safe_chomp(Value::String(text)),
            "chomp!" => {
                let changed = Self::chomp_text(&mut text.borrow_mut());
                if changed {
                    Value::String(text)
                } else {
                    Value::Nil
                }
            }
            "clear" => {
                text.borrow_mut().clear();
                Value::String(text)
            }
            "+" | "<<" | "concat" | "replace" => {
                let Value::String(other) = arguments.remove(0) else {
                    unreachable!("string operations require a proven string argument");
                };
                // Capture bytes first: self-append must not overlap immutable and mutable RefCell borrows.
                let other = other.borrow().clone();
                if name == "+" {
                    let mut result = text.borrow().clone();
                    result.push_str(&other);
                    Value::from(result)
                } else {
                    if name == "replace" {
                        *text.borrow_mut() = other;
                    } else {
                        text.borrow_mut().push_str(&other);
                    }
                    Value::String(text)
                }
            }
            _ => unreachable!("unknown string operation"),
        }
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
