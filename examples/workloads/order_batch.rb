# frozen_string_literal: true

class BatchLine
  attr_accessor :quantity

  def initialize(unit_price, quantity)
    @unit_price = unit_price
    @quantity = quantity
  end

  def subtotal
    @unit_price * @quantity
  end
end

catalog = [{ "sku" => "tea", "price" => 450 }, { "sku" => "coffee", "price" => 900 }]
orders = []
catalog.each do |product|
  line = BatchLine.new(product["price"], 2)
  orders.push({ "sku" => product["sku"], "line" => line, "notes" => ["packed".dup] })
end
orders[0]["line"].quantity = 3
orders[0]["notes"][0] << "!"
totals = orders.map do |order|
  puts "#{order['sku']}:#{order['line'].quantity}:#{order['notes'][0]}"
  order["line"].subtotal
end
if gets&.chomp == "gift"
  totals.push(200)
  nil
end
grand_total = 0
totals.each { |amount| grand_total += amount }
puts "lines:#{totals.length} total:#{grand_total} cents"
