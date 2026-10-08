# frozen_string_literal: true

class SharedNames
  def initialize(names)
    @names = names
  end

  def rename_first(name)
    @names[0].replace(name)
  end

  def add(name)
    @names.push(name)
  end

  def first
    @names[0]
  end
end

names = ["Ada".dup]
alias_name = names[0]
roster = SharedNames.new(names)
roster.rename_first("Zoë")
roster.add("Grace")
puts alias_name
puts roster.first == alias_name
puts names.length
puts names[-1]
puts "#{alias_name.length} characters / #{alias_name.bytesize} bytes"
