# frozen_string_literal: true

class Greeter
  def greet(name)
    message = "Hello, #{name}!"
    puts message
    message
  end
end

greeter = Greeter.new
greeter.greet("Ada")
