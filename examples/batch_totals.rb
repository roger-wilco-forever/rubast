# frozen_string_literal: true

class InvoiceLine
  def initialize(unit_price, quantity)
    @unit_price = unit_price
    @quantity = quantity
  end

  def subtotal
    @unit_price * @quantity
  end
end

lines = [InvoiceLine.new(1500, 2), InvoiceLine.new(1900, 1)]
# rubocop:disable-next Style/SymbolProc -- Rubast currently supports literal blocks, not Symbol-to-Proc.
subtotals = lines.map { |line| line.subtotal }
total = 0
lines.each { |line| total += line.subtotal }
discount = 0
3.times { |index| discount += index * 100 }
puts "subtotals:#{subtotals[0]},#{subtotals[1]}"
puts "total:#{total} discount:#{discount} cents"
