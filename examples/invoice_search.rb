# frozen_string_literal: true

class InvoiceBatch
  def each(subtotals)
    # rubocop:disable-next Style/ExplicitBlockArgument -- Explicit block forwarding is outside the current subset.
    subtotals.each { |subtotal| yield(subtotal) }
    puts "batch complete"
    self
  end
end

# rubocop:disable-next Style/OneClassPerFile -- A standalone example until require_relative is supported.
class InvoiceSearch
  def first_review(batch, subtotals)
    batch.each(subtotals) do |subtotal|
      puts "checking:#{subtotal}"
      return subtotal if subtotal >= 2500
    end
    nil
  end
end

puts "review:#{InvoiceSearch.new.first_review(InvoiceBatch.new, [1900, 3000, 4200])}"
puts "search complete"
