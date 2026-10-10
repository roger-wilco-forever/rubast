use rubast_runtime::{Runtime, Value};

fn allocate(runtime: &mut Runtime) -> Value {
    let node = runtime.new_object();
    let values = runtime.new_array(vec![node.clone(), Value::from("x".repeat(4096))]);
    let links = runtime.new_hash(vec![(Value::Symbol("values", ":values"), values)]);
    runtime.set_ivar(&node, "@links", links);
    node
}

fn main() {
    let arguments: Vec<_> = std::env::args().collect();
    let count: usize = arguments[1].parse().unwrap();
    let retain = arguments[2] == "retain";
    let mut runtime = Runtime::new();
    let root = runtime.new_array(vec![Value::Integer(7)]);
    runtime.set_constant("Root", root.clone());
    let mut checkpoints = Vec::new();
    let mut checksum = 0;
    for index in 1..=count {
        let node = allocate(&mut runtime);
        let links = runtime.get_ivar(&node, "@links");
        let values = runtime.hash_operation("[]", links, vec![Value::Symbol("values", ":values")]);
        let Value::Integer(length) = runtime.array_operation("length", values, vec![]) else {
            unreachable!()
        };
        checksum += length;
        if retain {
            runtime.array_operation("push", root.clone(), vec![node]);
        }
        if index % 1000 == 0 {
            let (live, slots) = runtime.heap_stats();
            checkpoints.push(format!("[{index},{live},{slots}]"));
        }
    }
    let reclaimed = runtime.collect_garbage();
    let (live, slots) = runtime.heap_stats();
    let Value::Integer(root_value) =
        runtime.array_operation("[]", runtime.constant("Root"), vec![Value::Integer(0)])
    else {
        unreachable!()
    };
    println!("{{\"checksum\":{checksum},\"root\":{root_value},\"retained_objects\":{live},\"arena_slots\":{slots},\"reclaimed_at_end\":{reclaimed},\"checkpoints\":[{}]}}", checkpoints.join(","));
}
