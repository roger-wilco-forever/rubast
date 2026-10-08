# frozen_string_literal: true

class DefinitionStore
  def initialize
    @entries = {}
  end

  def add(name, keys)
    @entries[name] = { keys: keys }
  end

  def entry(name)
    @entries[name]
  end

  def names
    @entries.keys
  end
end

store = DefinitionStore.new
keys = ["a".dup, "b"]
entry = store.add(:base, keys)
store.add(7, %w[x])
keys[0] << "!"
puts store.entry(:base)[:keys][0]
puts entry[:keys].length
puts store.names[0]
puts store.names[1]
