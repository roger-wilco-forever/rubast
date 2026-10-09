# frozen_string_literal: true

class Registry
  def initialize(name)
    @name = name
  end

  private

  def label
    "original:#{@name}"
  end

  def method_missing(name, *values)
    raise "Unknown operation: #{name}" unless name == :status

    "status:#{@name}:#{values.length}"
  end

  def respond_to_missing?(name, _include_private)
    name == :status
  end
end

entry = Registry.new(gets&.chomp)
puts entry.send(:label)
puts entry.respond_to?(:status)
puts entry.status

class Registry
  def label # rubocop:disable Lint/DuplicateMethods -- Exercise replacement after the first call.
    "updated:#{@name}"
  end
end

puts entry.label
puts entry.instance_variable_set(:@name, "replacement")
puts entry.instance_variable_get(:@name)
puts entry.status(1)
