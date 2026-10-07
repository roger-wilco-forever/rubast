# frozen_string_literal: true

class EmailChannel
  def deliver(name)
    "email:#{name}"
  end
end

class SmsChannel
  def deliver(name)
    "sms:#{name}"
  end
end

class Notification
  def initialize(channel)
    @channel = channel
  end

  def send_to(name)
    @channel.deliver(name)
  end
end

channel = if gets&.chomp == "sms"
            SmsChannel.new
          else
            EmailChannel.new
          end
puts Notification.new(channel).send_to("Ada")
