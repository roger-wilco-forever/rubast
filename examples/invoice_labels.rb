# frozen_string_literal: true

class InvoicePolicy
  def labels(subtotals)
    subtotals.map do |subtotal|
      # rubocop:disable-next Style/NumericPredicate -- Integer#zero? is outside the current subset.
      next "empty" if subtotal == 0
      next "review" if subtotal >= 2500

      "standard"
    end
  end
end

labels = InvoicePolicy.new.labels([0, 1900, 3000])
puts "statuses:#{labels[0]},#{labels[1]},#{labels[2]}"
