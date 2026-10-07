# frozen_string_literal: true

successful = 0
failed = 0
while (line = gets)
  if line&.chomp == "ok"
    successful += 1
  else
    failed += 1
  end
end
puts "successful:#{successful} failed:#{failed}"
