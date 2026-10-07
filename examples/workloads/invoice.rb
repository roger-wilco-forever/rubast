# frozen_string_literal: true

class Customer
  def initialize(name)
    @name = name
  end

  def label
    @name&.chomp
  end
end

class InvoiceLine
  def initialize(product, unit_price, quantity)
    @product = product
    @unit_price = unit_price
    @quantity = quantity
  end

  def change_quantity(quantity)
    @quantity = quantity
    self
  end

  def description
    "#{@quantity} x #{@product}"
  end

  def subtotal
    @unit_price * @quantity
  end
end

class Invoice
  def initialize(customer, line)
    @customer = customer
    @line = line
    @paid = false
  end

  def total
    @line.subtotal
  end

  def pay(amount)
    return "payment below total" if amount < total

    @paid = true
    "payment received"
  end

  def status
    if @paid
      "paid"
    else
      "unpaid"
    end
  end

  def summary
    "#{@customer.label}: #{@line.description}, #{total} cents, #{status}"
  end
end

customer = Customer.new("Ada")
line = InvoiceLine.new("Ruby book", 1500, 2)
invoice = Invoice.new(customer, line)
puts invoice.summary
puts invoice.pay(1000)
puts invoice.summary
line.change_quantity(3)
puts invoice.pay(4500)
puts invoice.summary
