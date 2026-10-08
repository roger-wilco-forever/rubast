# frozen_string_literal: true

class InvoiceBatch
  def initialize(subtotals)
    @subtotals = subtotals
  end

  def each
    # rubocop:disable-next Style/ExplicitBlockArgument -- Explicit block forwarding is outside the current subset.
    @subtotals.each { |subtotal| yield(subtotal) }
    self
  end
end

batch = InvoiceBatch.new([3000, 1900])
total = 0
returned = batch.each do |subtotal|
  puts "line:#{subtotal} cents"
  total += subtotal
end
puts "total:#{total} cents"
puts returned == batch
