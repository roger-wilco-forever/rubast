# frozen_string_literal: true

class ReceiptExport
  def initialize(path)
    @path = path
  end

  def save(customer, total)
    body = "Receipt for #{customer}\nTotal: #{total}\n"
    bytes = File.write(@path, body)
    warn "Saved #{bytes} bytes to #{@path}"
    $stdout.print(File.read(@path))
    bytes
  rescue SystemCallError => error
    warn "Export failed: #{error.message}"
    nil
  ensure
    $stdout.flush
  end
end

print "Customer: "
customer = $stdin.gets&.chomp
customer = "Guest" if customer.nil?
ReceiptExport.new("receipt.txt").save(customer, 1250)
