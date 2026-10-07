# frozen_string_literal: true

class LinkedName
  def initialize(text)
    @text = text
    @next = self
  end

  def connect(other)
    @next = other
    self
  end

  def follow
    @next
  end

  def rename(text)
    @text = text
    self
  end

  def label
    @text&.chomp
  end
end

first = LinkedName.new("Ada")
second = LinkedName.new("Zoë")
first.connect(second)
second.connect(first)
first.follow.follow.rename("Grace")
puts first.label
puts first.follow.label
puts first.follow.follow == first
