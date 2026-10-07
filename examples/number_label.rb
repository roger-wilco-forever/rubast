# frozen_string_literal: true

class NumberLabel
  def initialize(limit)
    @limit = limit
  end

  def describe(value)
    return "below:#{value}" if value < @limit

    if value == @limit
      "equal"
    else
      "above:#{value}"
    end
  end
end

label = NumberLabel.new(10)
puts label.describe(3 - 7)
puts label.describe(10)
puts label.describe(6 * 3)
