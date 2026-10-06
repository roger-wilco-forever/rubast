pub enum Value {
    Integer(i64),
}

pub struct Runtime;

impl Runtime {
    pub fn new() -> Self {
        Self
    }

    pub fn puts(&mut self, value: Value) {
        match value {
            Value::Integer(number) => println!("{number}"),
        }
    }
}
