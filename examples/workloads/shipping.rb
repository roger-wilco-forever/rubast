# frozen_string_literal: true

class Shipping
  def initialize(fee)
    @fee = fee
  end

  def total(subtotal)
    subtotal + @fee
  end
end

class ExpressShipping < Shipping
  def total(subtotal)
    super + 500
  end
end

puts "standard:#{Shipping.new(200).total(5000)}"
puts "express:#{ExpressShipping.new(200).total(5000)}"
