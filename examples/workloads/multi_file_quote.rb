# frozen_string_literal: true

require_relative "quote_app/preferred_quote"

quote = Shop::PreferredQuote.build("Ada", 1000, discount: 50) do |item|
  item.subtotal = item.subtotal + 200
  item
end
puts "#{quote.name}: #{quote.total}"
quote.discount = 100
puts quote.total
puts Shop::Quote.new("Roger", 500).total
