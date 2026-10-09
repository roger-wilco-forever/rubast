# frozen_string_literal: true

require_relative "../../examples/workloads/invoice"

name = gets&.chomp
name = "Guest" if name.nil?
customer = Customer.new(name)
line = InvoiceLine.new("Ruby book", 1500, 1)
invoice = Invoice.new(customer, line)
checksum = 0
summary = ""
index = 0
while index < 1_000_000
  line.change_quantity((index % 9) + 1)
  summary = invoice.summary
  checksum = (checksum % 1_000_003) + 1 if summary.bytesize > 128
  index += 1
end
puts summary
puts checksum
