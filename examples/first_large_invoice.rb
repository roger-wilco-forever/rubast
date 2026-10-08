# frozen_string_literal: true

class InvoiceBatch
  def initialize(subtotals)
    @subtotals = subtotals
  end

  def visit
    # rubocop:disable-next Style/ExplicitBlockArgument -- Explicit block forwarding is outside the current subset.
    @subtotals.each { |subtotal| yield(subtotal) }
    nil
  end
end

batch = InvoiceBatch.new([1900, 3000, 4200])
found = batch.visit do |subtotal|
  puts "checking:#{subtotal} cents"
  break subtotal if subtotal >= 2500
end
puts "first large invoice:#{found} cents"
puts "caller continues"
