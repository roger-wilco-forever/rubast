# frozen_string_literal: true

class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    message = "Hello, #{@name}!"
    puts message
    message
  end
end

greeter = Greeter.new("Ada")
greeter.greet
