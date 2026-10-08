# frozen_string_literal: true

count = 0
result = (count += 1 while count < 1000)
puts count
puts result
count -= 1 until count <= 997
puts count
puts count + 1
