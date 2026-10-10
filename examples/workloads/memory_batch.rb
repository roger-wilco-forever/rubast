# frozen_string_literal: true

class MemoryCell
  attr_accessor :links
  attr_reader :number

  def initialize(number)
    @number = number
  end
end

class MemoryBatch
  def self.discard(number)
    cell = MemoryCell.new(number)
    values = [cell, "packet:#{number}"]
    cell.links = { values: values }
    cell.links[:values][0].number
  end

  def self.run
    total = 0
    200.times { |number| total += discard(number) }
    total
  end
end

puts MemoryBatch.run
puts GC.start.nil?
