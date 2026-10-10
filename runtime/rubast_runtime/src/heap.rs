use crate::{Object, Value};
use std::ops::{Index, IndexMut};
use std::rc::{Rc, Weak};

#[derive(Clone, Debug)]
pub struct ObjectHandle(Rc<usize>);

impl PartialEq for ObjectHandle {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }
}
impl Eq for ObjectHandle {}

struct Slot {
    object: Option<Object>,
    handle: Weak<usize>,
}

pub(crate) struct Heap {
    slots: Vec<Slot>,
    free: Vec<usize>,
    allocations: usize,
    budget: usize,
}

impl Heap {
    pub fn new() -> Self {
        Self {
            slots: Vec::new(),
            free: Vec::new(),
            allocations: 0,
            budget: 256,
        }
    }

    pub fn stats(&self) -> (usize, usize) {
        (self.slots.len() - self.free.len(), self.slots.len())
    }

    pub fn allocate(&mut self, object: Object) -> Value {
        if self.allocations >= self.budget {
            self.collect();
        }
        let index = self.free.pop().unwrap_or(self.slots.len());
        let handle = Rc::new(index);
        let slot = Slot {
            object: Some(object),
            handle: Rc::downgrade(&handle),
        };
        if index == self.slots.len() {
            self.slots.push(slot);
        } else {
            self.slots[index] = slot;
        }
        self.allocations += 1;
        Value::Object(ObjectHandle(handle))
    }

    pub fn collect(&mut self) -> usize {
        let mut incoming = vec![0; self.slots.len()];
        for slot in &self.slots {
            if let Some(object) = &slot.object {
                object.edges(|handle| incoming[self.index(handle)] += 1);
            }
        }
        // shortcut: temporaries stay roots until Rust scope exit; shorten lifetimes if batch retention matters.
        let mut work: Vec<_> = self
            .slots
            .iter()
            .enumerate()
            .filter_map(|(index, slot)| {
                (slot.object.is_some() && slot.handle.strong_count() > incoming[index])
                    .then_some(index)
            })
            .collect();
        let mut marked = vec![false; self.slots.len()];
        while let Some(index) = work.pop() {
            if !marked[index] {
                marked[index] = true;
                self.slots[index]
                    .object
                    .as_ref()
                    .unwrap()
                    .edges(|handle| work.push(self.index(handle)));
            }
        }
        let mut reclaimed = 0;
        for (index, slot) in self.slots.iter_mut().enumerate() {
            if slot.object.is_some() && !marked[index] {
                slot.object = None;
                slot.handle = Weak::new();
                self.free.push(index);
                reclaimed += 1;
            }
        }
        self.allocations = 0;
        self.budget = 256.max(self.stats().0.saturating_mul(2));
        reclaimed
    }

    fn index(&self, handle: &ObjectHandle) -> usize {
        let index = *handle.0;
        assert!(std::ptr::eq(
            self.slots[index].handle.as_ptr(),
            Rc::as_ptr(&handle.0)
        ));
        index
    }
}

impl Index<&ObjectHandle> for Heap {
    type Output = Object;

    fn index(&self, handle: &ObjectHandle) -> &Self::Output {
        self.slots[self.index(handle)].object.as_ref().unwrap()
    }
}

impl IndexMut<&ObjectHandle> for Heap {
    fn index_mut(&mut self, handle: &ObjectHandle) -> &mut Self::Output {
        let index = self.index(handle);
        self.slots[index].object.as_mut().unwrap()
    }
}

impl Object {
    fn edges(&self, mut visit: impl FnMut(&ObjectHandle)) {
        let mut value = |value: &Value| {
            if let Value::Object(handle) = value {
                visit(handle);
            }
        };
        match self {
            Self::Instance(fields) => fields.values().for_each(value),
            Self::Array(values) => values.iter().for_each(value),
            Self::Hash(entries) => entries.iter().for_each(|(key, entry)| {
                value(key);
                value(entry);
            }),
        }
    }
}
