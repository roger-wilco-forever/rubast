use crate::Value;

mod nonprintable;

pub(super) fn inspect(value: Value) -> String {
    match value {
        Value::Nil => "nil".into(),
        Value::Symbol(_, inspected) => inspected.into(),
        Value::String(text) => inspect_string(&text.borrow()),
        value => value.into_ruby_string(),
    }
}

fn inspect_string(text: &str) -> String {
    let mut output = String::from("\"");
    let mut characters = text.chars().peekable();
    while let Some(character) = characters.next() {
        let escaped = match character {
            '\x07' => Some("\\a"),
            '\x08' => Some("\\b"),
            '\t' => Some("\\t"),
            '\n' => Some("\\n"),
            '\x0b' => Some("\\v"),
            '\x0c' => Some("\\f"),
            '\r' => Some("\\r"),
            '\x1b' => Some("\\e"),
            '\\' => Some("\\\\"),
            '"' => Some("\\\""),
            '#' if matches!(characters.peek(), Some('{' | '$' | '@')) => Some("\\#"),
            _ => None,
        };
        if let Some(escaped) = escaped {
            output.push_str(escaped);
        } else {
            let point = character as u32;
            let index = nonprintable::RANGES.partition_point(|(_, end)| *end < point);
            if nonprintable::RANGES
                .get(index)
                .is_some_and(|(start, _)| *start <= point)
            {
                if point <= 0xffff {
                    output.push_str(&format!("\\u{point:04X}"));
                } else {
                    output.push_str(&format!("\\u{{{point:X}}}"));
                }
            } else {
                output.push(character);
            }
        }
    }
    output.push('"');
    output
}
