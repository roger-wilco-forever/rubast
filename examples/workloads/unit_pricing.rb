# frozen_string_literal: true

class UnitPricing
  def initialize(minimum_quantity)
    @minimum_quantity = minimum_quantity
  end

  def per_item(subtotal, quantity)
    return "quantity must be at least #{@minimum_quantity}" if quantity < @minimum_quantity

    subtotal / quantity
  end
end

pricing = UnitPricing.new(1)
puts pricing.per_item(10_000, 3)
puts pricing.per_item(10_000, 0)
