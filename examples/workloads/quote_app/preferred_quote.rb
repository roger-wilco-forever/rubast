# frozen_string_literal: true

require_relative "quote"

class Shop::PreferredQuote < Shop::Quote
  prepend Shop::Loyalty
end
