# frozen_string_literal: true

class CartItem
  def initialize(unit_price, quantity)
    @unit_price = unit_price
    @quantity = quantity
  end

  def subtotal
    @unit_price * @quantity
  end
end

class ShoppingCart
  def initialize
    @items = []
  end

  def add(item)
    @items << item
    self
  end

  def total
    @items.sum(&:subtotal)
  end
end

cart = ShoppingCart.new
cart.add(CartItem.new(1500, 2)).add(CartItem.new(1900, 1))
puts "total:#{cart.total} cents"
