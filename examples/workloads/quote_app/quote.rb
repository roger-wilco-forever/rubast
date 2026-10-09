# frozen_string_literal: true

require_relative "shop"

class Shop::Quote
  include Shop::Totals

  attr_reader :name
  attr_accessor :subtotal, :discount

  def initialize(name, subtotal, discount: 0)
    @name = name
    @subtotal = subtotal
    @discount = discount
  end

  def self.build(name, subtotal, discount: 0, &callback)
    quote = new(name, subtotal, discount: discount)
    callback.call(quote)
  end
end
