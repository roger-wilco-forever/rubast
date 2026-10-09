# frozen_string_literal: true

labels = { "ok" => "accepted", "error" => "rejected" }
statuses = []
3.times do
  line = gets&.chomp
  if line == "ok"
    statuses.push("ok")
    nil
  elsif line == "error"
    statuses.push("error")
    nil
  end
end
successful = 0
failed = 0
statuses.each do |status|
  puts labels[status]
  if status == "ok"
    successful += 1
  else
    failed += 1
  end
end
puts "processed:#{statuses.length} successful:#{successful} failed:#{failed}"
