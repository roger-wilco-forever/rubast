# frozen_string_literal: true

class Base
  def self.defs
    @defs
  end

  def self.add
    @defs = defs + [{ keys: ["a", "b"] }]
  end

  def self.clear
    @defs = []
  end

  @defs = []
  add
end

class Child < Base
  def self.defs
    @defs.nil? ? Base.defs : @defs
  end
end

parent = Base.defs
p(parent[0][:keys] == ["a", "b"])
