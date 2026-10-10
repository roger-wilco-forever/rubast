use rubast_runtime::{Flow, Location, Runtime, Value};
use std::rc::Rc;

fn cycle(runtime: &mut Runtime) -> Value {
    let node = runtime.new_object();
    let values = runtime.new_array(vec![node.clone(), Value::from("payload".repeat(1024))]);
    let hash = runtime.new_hash(vec![(Value::Symbol("links", ":links"), values)]);
    runtime.set_ivar(&node, "@links", hash);
    node
}

#[test]
fn unreachable_mixed_cycles_release_objects_and_string_buffers() {
    let mut runtime = Runtime::new();
    let node = cycle(&mut runtime);
    let hash = runtime.get_ivar(&node, "@links");
    let values = runtime.hash_operation("[]", hash, vec![Value::Symbol("links", ":links")]);
    let Value::String(text) = runtime.array_operation("[]", values, vec![Value::Integer(1)]) else {
        unreachable!()
    };
    let weak_text = Rc::downgrade(&text);
    drop(text);
    drop(node);
    assert_eq!(runtime.collect_garbage(), 3);
    assert_eq!(runtime.heap_stats(), (0, 3));
    assert!(weak_text.upgrade().is_none());
    assert_eq!(runtime.collect_garbage(), 0);
}

#[test]
fn constants_and_duplicate_edges_preserve_aliases() {
    let mut runtime = Runtime::new();
    let node = cycle(&mut runtime);
    runtime.set_ivar(&node, "@alias", node.clone());
    runtime.set_ivar(&node, "@another_alias", node.clone());
    runtime.set_constant("Saved", node);
    assert_eq!(runtime.collect_garbage(), 0);
    let node = runtime.constant("Saved");
    let alias = runtime.get_ivar(&node, "@alias");
    runtime.set_ivar(&alias, "@number", Value::Integer(7));
    assert_eq!(runtime.get_ivar(&node, "@number"), Value::Integer(7));
    assert_eq!(runtime.heap_stats().0, 3);
}

#[test]
fn automatic_collection_reuses_slots_during_sustained_allocation() {
    let mut runtime = Runtime::new();
    let root = cycle(&mut runtime);
    for _ in 0..20_000 {
        drop(cycle(&mut runtime));
        assert!(runtime.heap_stats().1 <= 262);
    }
    runtime.collect_garbage();
    assert_eq!(runtime.heap_stats().0, 3);
    let hash = runtime.get_ivar(&root, "@links");
    let values = runtime.hash_operation("[]", hash, vec![Value::Symbol("links", ":links")]);
    assert_eq!(
        runtime.array_operation("[]", values, vec![Value::Integer(0)]),
        root
    );
}

#[test]
fn allocation_payload_and_argument_copies_are_roots() {
    let mut runtime = Runtime::new();
    let node = cycle(&mut runtime);
    // Fill the allocation budget so inserting the pending array triggers collection.
    for _ in 0..253 {
        drop(runtime.new_object());
    }
    let array = runtime.new_array(vec![node]);
    let copy = runtime.copy_argument("array", array);
    let node = runtime.array_operation("[]", copy, vec![Value::Integer(0)]);
    assert_eq!(runtime.collect_garbage(), 2);
    assert_eq!(runtime.heap_stats().0, 3);
    assert_ne!(runtime.get_ivar(&node, "@links"), Value::Nil);
}

#[test]
fn hash_keys_and_values_both_retain_objects() {
    let mut runtime = Runtime::new();
    let key = runtime.new_object();
    let value = runtime.new_object();
    let hash = runtime.new_hash(vec![(key, value)]);
    assert_eq!(runtime.collect_garbage(), 0);
    let keys = runtime.hash_operation("keys", hash.clone(), vec![]);
    let key = runtime.array_operation("[]", keys, vec![Value::Integer(0)]);
    let value = runtime.hash_operation("[]", hash, vec![key]);
    runtime.set_ivar(&value, "@number", Value::Integer(7));
    assert_eq!(runtime.get_ivar(&value, "@number"), Value::Integer(7));
    drop(value);
    assert_eq!(runtime.collect_garbage(), 4);
}

#[test]
fn pending_outcomes_exits_and_exception_contexts_are_roots() {
    let mut runtime = Runtime::new();
    let outcome = Ok::<_, Flow>(cycle(&mut runtime));
    let exit = Flow::Exit("return", cycle(&mut runtime));
    // Native runtime stress case: Ruby validation only accepts scalar exception messages.
    let error = Runtime::exception("RuntimeError", cycle(&mut runtime));
    let Err(Flow::Exception(error)) =
        runtime.raise(Some(error), Location::new("memory.rb", 1, "test"))
    else {
        unreachable!()
    };
    runtime.enter_exception(error);
    assert_eq!(runtime.collect_garbage(), 0);
    drop(outcome);
    drop(exit);
    assert_eq!(runtime.collect_garbage(), 6);
    runtime.leave_exception();
    assert_eq!(runtime.collect_garbage(), 3);
}

#[test]
fn deep_graphs_are_marked_without_recursive_traversal() {
    let mut runtime = Runtime::new();
    let root = runtime.new_object();
    let mut tail = root.clone();
    for _ in 0..20_000 {
        let next = runtime.new_object();
        runtime.set_ivar(&tail, "@next", next.clone());
        tail = next;
    }
    drop(tail);
    assert_eq!(runtime.collect_garbage(), 0);
    assert_eq!(runtime.heap_stats().0, 20_001);
    drop(root);
    assert_eq!(runtime.collect_garbage(), 20_001);
}
