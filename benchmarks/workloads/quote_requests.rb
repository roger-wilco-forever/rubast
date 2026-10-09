# frozen_string_literal: true

require_relative "../../examples/workloads/quote_app/preferred_quote"

name = gets&.chomp
name = "Guest" if name.nil?
quote = Shop::PreferredQuote.build(name, 1000, discount: 50) { |item| item }
checksum = 0
index = 0
while index < 1_000_000
  quote.subtotal = 1000 + (index % 1000)
  quote.discount = index % 100
  checksum = (checksum % 1_000_003) + quote.total
  index += 1
end
puts "#{quote.name}: #{quote.total}"
puts checksum
