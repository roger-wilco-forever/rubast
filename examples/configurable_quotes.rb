# frozen_string_literal: true

class QuoteCalculator
  def initialize(currency: "USD", fee: 250, &configure)
    @currency = currency
    @fee = if configure
             configure.call(fee)
           else
             fee
           end
  end

  def total(unit_price, quantity = 1, *charges, discount: 0, **metadata, &after)
    subtotal = unit_price * quantity
    charges.each { |charge| subtotal += charge }
    subtotal += @fee
    subtotal -= discount
    result = "#{metadata[:reference]} #{@currency} #{subtotal}"
    if after
      after.call(result)
    else
      result
    end
  end

  # Named forwarding demonstrates the current compiler subset.
  # rubocop:disable-next Style/ArgumentsForwarding, Naming/BlockForwarding
  def forward(values, **options, &callback)
    # rubocop:disable-next Style/ArgumentsForwarding, Naming/BlockForwarding
    total(*values, **options, &callback)
  end
end

calculator = QuoteCalculator.new { |fee| fee + 50 }
puts calculator.total(1200, reference: "default")
values = [1200, 2, 150, 75]
puts calculator.forward(values, discount: 100, reference: "order-7") { |quote| "approved: #{quote}" }
puts values.length
begin
  calculator.total(reference: "missing-price")
rescue ArgumentError => error
  puts "rejected: #{error.message}"
end
