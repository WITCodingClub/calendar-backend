# frozen_string_literal: true

namespace :risc do
  # Runs one call of Risc::StreamClient and stops the task with a message when
  # it fails.
  def risc_stream
    yield Risc::StreamClient.new
  rescue Risc::StreamClient::Error => e
    puts "✗ #{e.message}"
    exit 1
  end

  desc "Configure Google RISC stream (register endpoint and subscribe to events)"
  task configure: :environment do
    receiver_url = ENV["RISC_RECEIVER_URL"]
    if receiver_url.blank?
      puts "ERROR: RISC_RECEIVER_URL environment variable not set"
      puts "Set it to your public RISC webhook URL, e.g.:"
      puts "  export RISC_RECEIVER_URL=https://yourapp.com/risc/events"
      exit 1
    end

    risc_stream { |client| client.configure(receiver_url) }
    puts "✓ RISC stream configured successfully!"
    puts "  Endpoint: #{receiver_url}"
    puts "  Events subscribed: #{SecurityEvent::ALL_EVENT_TYPES.length}"
  end

  desc "Get current RISC stream configuration"
  task status: :environment do
    puts JSON.pretty_generate(risc_stream(&:stream))
  end

  desc "Test RISC stream by requesting a verification event"
  task test: :environment do
    state = "Test verification at #{Time.current.iso8601}"
    risc_stream { |client| client.verify(state) }
    puts "✓ Test event sent successfully!"
    puts "  State: #{state}"
  end

  desc "Enable RISC stream"
  task enable: :environment do
    risc_stream { |client| client.update_status("enabled") }
    puts "✓ RISC stream enabled"
  end

  desc "Disable RISC stream"
  task disable: :environment do
    risc_stream { |client| client.update_status("disabled") }
    puts "✓ RISC stream disabled"
  end

  desc "List recent security events"
  task list: :environment do
    events = SecurityEvent.recent.limit(50)
    if events.empty?
      puts "No security events found"
      exit 0
    end

    puts "Recent security events (#{events.count}):\n"
    puts "%-25s %-40s %-15s %-10s %s" % [ "Created", "Event Type", "Reason", "Processed", "User" ]
    puts "-" * 120

    events.each do |event|
      user_display = event.user ? "#{event.user.email} (#{event.user.id})" : "Unknown"
      puts "%-25s %-40s %-15s %-10s %s" % [
        event.created_at.strftime("%Y-%m-%d %H:%M:%S"),
        event.event_type_name,
        event.reason || "N/A",
        event.processed ? "Yes" : "No",
        user_display
      ]
    end
  end

  desc "Clean up expired security events"
  task cleanup: :environment do
    puts "Cleaning up expired security events..."

    expired = SecurityEvent.expired
    count = expired.count

    if count.zero?
      puts "No expired events to clean up"
      exit 0
    end

    puts "Found #{count} expired event(s)"
    expired.destroy_all
    puts "✓ Deleted #{count} expired security event(s)"
  end

  desc "Show statistics about security events"
  task stats: :environment do
    total       = SecurityEvent.count
    processed   = SecurityEvent.processed.count
    unprocessed = SecurityEvent.unprocessed.count

    puts "Security Event Statistics:"
    puts "  Total events:  #{total}"
    puts "  Processed:     #{processed}"
    puts "  Unprocessed:   #{unprocessed}"
    puts ""

    puts "Events by type:"
    SecurityEvent.group(:event_type).count.each do |type, count|
      puts "  #{type.split('/').last}: #{count}"
    end

    puts ""
    puts "Events by reason:"
    SecurityEvent.where.not(reason: nil).group(:reason).count.each do |reason, count|
      puts "  #{reason}: #{count}"
    end
  end
end
