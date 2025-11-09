# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

namespace :risc do
  desc "Configure Google RISC stream (register endpoint and subscribe to events)"
  task configure: :environment do
    puts "Configuring Google RISC stream..."

    # Get the receiver endpoint URL
    receiver_url = ENV["RISC_RECEIVER_URL"]
    if receiver_url.blank?
      puts "ERROR: RISC_RECEIVER_URL environment variable not set"
      puts "Set it to your public RISC webhook URL, e.g.:"
      puts "  export RISC_RECEIVER_URL=https://yourapp.com/risc/events"
      exit 1
    end

    # Get service account credentials path
    credentials_path = ENV["GOOGLE_SERVICE_ACCOUNT_KEY_PATH"] || "config/service_account_key.json"
    unless File.exist?(credentials_path)
      puts "ERROR: Service account credentials not found at #{credentials_path}"
      puts "Set GOOGLE_SERVICE_ACCOUNT_KEY_PATH to the path of your service account JSON key"
      exit 1
    end

    # Events to subscribe to
    events = [
      SecurityEvent::SESSIONS_REVOKED,
      SecurityEvent::TOKENS_REVOKED,
      SecurityEvent::TOKEN_REVOKED,
      SecurityEvent::ACCOUNT_DISABLED,
      SecurityEvent::ACCOUNT_ENABLED,
      SecurityEvent::ACCOUNT_CREDENTIAL_CHANGE_REQUIRED,
      SecurityEvent::VERIFICATION
    ]

    # Create authorization token
    auth_token = create_risc_auth_token(credentials_path)

    # Configure the stream
    config = {
      delivery: {
        delivery_method: "https://schemas.openid.net/secevent/risc/delivery-method/push",
        url: receiver_url
      },
      events_requested: events
    }

    uri = URI.parse("https://risc.googleapis.com/v1beta/stream:update")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{auth_token}"
    request.body = config.to_json

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      puts "✓ RISC stream configured successfully!"
      puts "  Endpoint: #{receiver_url}"
      puts "  Events subscribed: #{events.length}"
    else
      puts "✗ Failed to configure RISC stream"
      puts "  Status: #{response.code} #{response.message}"
      puts "  Body: #{response.body}"
      exit 1
    end
  end

  desc "Get current RISC stream configuration"
  task status: :environment do
    puts "Fetching RISC stream configuration..."

    credentials_path = ENV["GOOGLE_SERVICE_ACCOUNT_KEY_PATH"] || "config/service_account_key.json"
    unless File.exist?(credentials_path)
      puts "ERROR: Service account credentials not found at #{credentials_path}"
      exit 1
    end

    auth_token = create_risc_auth_token(credentials_path)

    uri = URI.parse("https://risc.googleapis.com/v1beta/stream")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.path)
    request["Authorization"] = "Bearer #{auth_token}"

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      config = JSON.parse(response.body)
      puts "✓ Current RISC configuration:"
      puts JSON.pretty_generate(config)
    else
      puts "✗ Failed to fetch RISC configuration"
      puts "  Status: #{response.code} #{response.message}"
      puts "  Body: #{response.body}"
    end
  end

  desc "Test RISC stream by requesting a verification event"
  task test: :environment do
    puts "Sending test verification event..."

    credentials_path = ENV["GOOGLE_SERVICE_ACCOUNT_KEY_PATH"] || "config/service_account_key.json"
    unless File.exist?(credentials_path)
      puts "ERROR: Service account credentials not found at #{credentials_path}"
      exit 1
    end

    auth_token = create_risc_auth_token(credentials_path)

    test_data = {
      state: "Test verification at #{Time.current.iso8601}"
    }

    uri = URI.parse("https://risc.googleapis.com/v1beta/stream:verify")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{auth_token}"
    request.body = test_data.to_json

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      puts "✓ Test event sent successfully!"
      puts "  Check your RISC endpoint logs for the verification event"
      puts "  State: #{test_data[:state]}"
    else
      puts "✗ Failed to send test event"
      puts "  Status: #{response.code} #{response.message}"
      puts "  Body: #{response.body}"
    end
  end

  desc "Enable RISC stream"
  task enable: :environment do
    update_stream_status("enabled")
  end

  desc "Disable RISC stream"
  task disable: :environment do
    update_stream_status("disabled")
  end

  desc "List recent security events"
  task list: :environment do
    events = SecurityEvent.recent.limit(50)

    if events.empty?
      puts "No security events found"
      exit 0
    end

    puts "Recent security events (#{events.count}):\n"
    puts "%-25s %-40s %-15s %-10s %s" % ["Created", "Event Type", "Reason", "Processed", "User"]
    puts "-" * 120

    events.each do |event|
      event_type_name = event.event_type_name
      user_display = event.user ? "#{event.user.email} (#{event.user.id})" : "Unknown"

      puts "%-25s %-40s %-15s %-10s %s" % [
        event.created_at.strftime("%Y-%m-%d %H:%M:%S"),
        event_type_name,
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
    total = SecurityEvent.count
    processed = SecurityEvent.processed.count
    unprocessed = SecurityEvent.unprocessed.count

    puts "Security Event Statistics:"
    puts "  Total events: #{total}"
    puts "  Processed: #{processed}"
    puts "  Unprocessed: #{unprocessed}"
    puts ""

    # Events by type
    puts "Events by type:"
    SecurityEvent.group(:event_type).count.each do |event_type, count|
      event_type_name = event_type.split("/").last
      puts "  #{event_type_name}: #{count}"
    end
    puts ""

    # Events by reason
    puts "Events by reason:"
    SecurityEvent.where.not(reason: nil).group(:reason).count.each do |reason, count|
      puts "  #{reason}: #{count}"
    end
  end

  # Helper method to create RISC API authorization token
  def create_risc_auth_token(credentials_path)
    credentials = JSON.parse(File.read(credentials_path))

    # Create JWT
    iat = Time.current.to_i
    exp = iat + 3600 # 1 hour

    payload = {
      iss: credentials["client_email"],
      sub: credentials["client_email"],
      aud: "https://risc.googleapis.com/google.identity.risc.v1beta.RiscManagementService",
      iat: iat,
      exp: exp
    }

    # Sign with private key
    private_key = OpenSSL::PKey::RSA.new(credentials["private_key"])
    JWT.encode(payload, private_key, "RS256", kid: credentials["private_key_id"])
  end

  # Helper method to update stream status
  def update_stream_status(status)
    puts "#{status.capitalize}ing RISC stream..."

    credentials_path = ENV["GOOGLE_SERVICE_ACCOUNT_KEY_PATH"] || "config/service_account_key.json"
    unless File.exist?(credentials_path)
      puts "ERROR: Service account credentials not found at #{credentials_path}"
      exit 1
    end

    auth_token = create_risc_auth_token(credentials_path)

    status_data = { status: status }

    uri = URI.parse("https://risc.googleapis.com/v1beta/stream/status:update")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{auth_token}"
    request.body = status_data.to_json

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      puts "✓ RISC stream #{status}d successfully!"
    else
      puts "✗ Failed to #{status} RISC stream"
      puts "  Status: #{response.code} #{response.message}"
      puts "  Body: #{response.body}"
      exit 1
    end
  end
end
