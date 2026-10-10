# frozen_string_literal: true

class CallbackLine
  attr_reader :label

  def initialize(unit_price, quantity)
    @unit_price = unit_price
    @quantity = quantity
    @label = "pending".dup
  end

  def subtotal
    @unit_price * @quantity
  end

  def pack
    @label.replace("packed")
    GC.start
  end
end

class DeliveryLine < CallbackLine
  def subtotal
    super + 200
  end
end

lines = [CallbackLine.new(450, 3), DeliveryLine.new(900, 2)]
amounts = lines.map(&:subtotal)
lines.each(&:pack)
labels = lines.map(&:label)
puts "#{labels[0]}/#{labels[1]}"
total = 0
amounts.each { |amount| total += amount }
puts "total:#{total} cents"
