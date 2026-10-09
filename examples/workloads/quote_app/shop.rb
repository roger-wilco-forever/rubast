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
end
