# frozen_string_literal: true

module Shop
  TAX_PERCENT = 10

  module Totals
    def total
      subtotal + tax
    end

    private

    def tax
      subtotal * TAX_PERCENT / 100
    end
  end

  module Loyalty
    def total
      super - discount
    end
  end

  class Quote
    include Totals

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

  class PreferredQuote < Quote
    prepend Loyalty
  end
end

quote = Shop::PreferredQuote.build("Ada", 1000, discount: 50) do |item|
  item.subtotal = item.subtotal + 200
  item
end
puts "#{quote.name}: #{quote.total}"
quote.discount = 100
puts quote.total
puts Shop::Quote.new("Roger", 500).total
