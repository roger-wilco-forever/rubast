# frozen_string_literal: true

class PriceQuote
  def calculate(subtotal, quantity)
    subtotal / quantity
  rescue ZeroDivisionError => error
    puts "invalid quantity: #{error.message}; retrying with one item"
    quantity = 1
    retry
  ensure
    puts "quote complete: quantity=#{quantity}"
  end
end

quote = PriceQuote.new
puts "unit price: #{quote.calculate(2400, 0)}"
puts "unit price: #{quote.calculate(2400, 3)}"
