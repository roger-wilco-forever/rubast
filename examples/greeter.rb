# frozen_string_literal: true

class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    message = self.message
    puts message
    message
  end

  def message
    "Hello, #{name}!"
  end

  def name
    @name&.chomp
  end
end

greeter = Greeter.new("Ada")
greeter.greet
