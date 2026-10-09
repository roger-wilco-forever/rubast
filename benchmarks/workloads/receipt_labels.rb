# frozen_string_literal: true

customer = gets&.chomp
customer = "Guest" if customer.nil?
checksum = 0
body = ""
index = 0
while index < 1_000_000
  total = 1000 + (index % 1000)
  body = "Receipt for #{customer}\nTotal: #{total}\n"
  checksum = (checksum % 1_000_003) + 1 if body.bytesize > 128
  index += 1
end
puts body
puts checksum
