use crate::{Runtime, Value};
use std::cell::RefCell;
use std::rc::Rc;

pub type ErrorRef = Rc<RefCell<RubyError>>;
pub type Outcome = Result<Value, Flow>;

#[derive(Clone, Debug)]
pub struct Location {
    pub path: &'static str,
    pub line: usize,
    pub label: &'static str,
    pub highlight: &'static str,
    pub name_highlight: &'static str,
}

impl PartialEq for Location {
    fn eq(&self, other: &Self) -> bool {
        self.path == other.path && self.line == other.line && self.label == other.label
    }
}
impl Eq for Location {}

impl Location {
    pub fn new(path: &'static str, line: usize, label: &'static str) -> Self {
        Self {
            path,
            line,
            label,
            highlight: "",
            name_highlight: "",
        }
    }
    pub fn highlight(mut self, highlight: &'static str) -> Self {
        self.highlight = highlight;
        self
    }
    pub fn name_highlight(mut self, highlight: &'static str) -> Self {
        self.name_highlight = highlight;
        self
    }
    fn render(&self) -> String {
        format!("{}:{}:in '{}'", self.path, self.line, self.label)
    }
}

#[derive(Clone, Debug)]
pub struct RubyError {
    pub class: &'static str,
    pub message: Value,
    pub trace: Vec<Location>,
    pub cause: Option<ErrorRef>,
}

impl PartialEq for RubyError {
    fn eq(&self, other: &Self) -> bool {
        self.class == other.class && self.message == other.message && self.trace == other.trace
    }
}
impl Eq for RubyError {}

#[derive(Clone, Debug)]
pub enum Flow {
    Exception(ErrorRef),
    Exit(&'static str, Value),
}

impl Runtime {
    pub fn exception(class: &'static str, message: Value) -> Value {
        Value::Exception(Rc::new(RefCell::new(RubyError {
            class,
            message,
            trace: Vec::new(),
            cause: None,
        })))
    }

    pub fn exception_message(value: Value) -> Value {
        let Value::Exception(error) = value else {
            unreachable!("exception messages require a validated exception");
        };
        let message = error.borrow().message.clone();
        message
    }

    pub fn raise(&mut self, value: Option<Value>, location: Location) -> Outcome {
        let value = match value {
            Some(Value::Exception(error)) => Value::Exception(error),
            Some(message) => Self::exception("RuntimeError", message),
            None => self
                .current_exception()
                .unwrap_or_else(|| Self::exception("RuntimeError", Value::from(String::new()))),
        };
        let Value::Exception(error) = value else {
            unreachable!()
        };
        {
            let mut data = error.borrow_mut();
            if data.trace.is_empty() {
                data.trace.push(location);
                data.trace.extend(self.frames.iter().rev().cloned());
            }
            if data.cause.is_none() {
                if let Some(Value::Exception(cause)) = self.current_exception() {
                    if !Self::cause_contains(&cause, &error) {
                        data.cause = Some(cause);
                    }
                }
            }
        }
        Err(Flow::Exception(error))
    }

    fn cause_contains(cause: &ErrorRef, target: &ErrorRef) -> bool {
        let mut current = Some(cause.clone());
        while let Some(error) = current {
            if Rc::ptr_eq(&error, target) {
                return true;
            }
            current = error.borrow().cause.clone();
        }
        false
    }

    pub fn runtime_error(
        &mut self,
        class: &'static str,
        message: String,
        location: Location,
    ) -> Outcome {
        self.raise(Some(Self::exception(class, Value::from(message))), location)
    }

    pub fn current_exception(&self) -> Option<Value> {
        self.exceptions.last().cloned().map(Value::Exception)
    }

    pub fn enter_exception(&mut self, error: ErrorRef) {
        self.exceptions.push(error);
    }
    pub fn leave_exception(&mut self) {
        self.exceptions.pop();
    }
    #[inline]
    pub fn enter(&mut self, location: Location) {
        self.frames.push(location);
    }
    pub fn leave(&mut self) {
        self.frames.pop();
    }

    pub fn take_call_site(&mut self) -> Location {
        self.frames
            .pop()
            .expect("callback requires a receiving frame")
    }

    pub fn matches(error: &ErrorRef, classes: &[&str]) -> bool {
        let mut name = Some(error.borrow().class);
        while let Some(class) = name {
            if classes.contains(&class) {
                return true;
            }
            name = match class {
                "Exception" => None,
                "StandardError" => Some("Exception"),
                "FrozenError" => Some("RuntimeError"),
                "NoMethodError" => Some("NameError"),
                "EOFError" => Some("IOError"),
                "Encoding::InvalidByteSequenceError" => Some("EncodingError"),
                name if name.starts_with("Errno::") => Some("SystemCallError"),
                _ => Some("StandardError"),
            };
        }
        false
    }

    pub fn finish(result: Outcome) {
        if let Err(flow) = result {
            match flow {
                Flow::Exception(error) => {
                    eprint!("{}", Self::render_error(&error));
                    std::process::exit(1);
                }
                Flow::Exit(_, _) => unreachable!("unresolved validated control target"),
            }
        }
    }

    fn render_error(error: &ErrorRef) -> String {
        let error = error.borrow();
        let mut output = String::new();
        if let Some(first) = error.trace.first() {
            let mut message = error.message.clone().into_ruby_string();
            if matches!(error.class, "ArgumentError" | "TypeError") {
                message.push_str(first.highlight);
            }
            if matches!(error.class, "NameError" | "NoMethodError") {
                message.push_str(first.name_highlight);
            }
            if error.class == "RuntimeError" && message.is_empty() {
                output.push_str(&format!("{}: unhandled exception\n", first.render()));
            } else {
                let (first_line, rest) = message.split_once('\n').unwrap_or((&message, ""));
                output.push_str(&format!(
                    "{}: {} ({})\n",
                    first.render(),
                    first_line,
                    error.class
                ));
                if !rest.is_empty() {
                    output.push_str(rest);
                    output.push('\n');
                }
            }
            for frame in error.trace.iter().skip(1) {
                output.push_str(&format!("\tfrom {}\n", frame.render()));
            }
        }
        if let Some(cause) = &error.cause {
            output.push_str(&Self::render_error(cause));
        }
        output
    }
}
