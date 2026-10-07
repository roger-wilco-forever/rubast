# frozen_string_literal: true

class Greeter
  def greet(name)
    "Hello, #{name}!"
  end
end

greeter = Greeter.new
puts greeter.greet("Ada")
