# frozen_string_literal: true

require "net/http"

module Risc
  # The RISC stream management API of Google
  # (https://developers.google.com/identity/protocols/risc). It sets where
  # Google sends security events for our users and which events it sends. The
  # risc:* rake tasks call it. It signs each call with the service account key
  # in GOOGLE_SERVICE_ACCOUNT_KEY_PATH.
  class StreamClient
    BASE_URL = "https://risc.googleapis.com/v1beta/"
    TOKEN_AUDIENCE = "https://risc.googleapis.com/google.identity.risc.v1beta.RiscManagementService"
    DEFAULT_KEY_PATH = "config/service_account_key.json"
    PUSH_DELIVERY = "https://schemas.openid.net/secevent/risc/delivery-method/push"

    class Error < StandardError; end

    def self.key_path = ENV.fetch("GOOGLE_SERVICE_ACCOUNT_KEY_PATH", DEFAULT_KEY_PATH)

    def initialize(key_path: self.class.key_path)
      raise Error, "Service account credentials not found at #{key_path}" unless File.exist?(key_path)

      @credentials = JSON.parse(File.read(key_path))
    end

    # Sends every SecurityEvent type to receiver_url.
    def configure(receiver_url)
      post("stream:update", delivery: { delivery_method: PUSH_DELIVERY, url: receiver_url },
                            events_requested: SecurityEvent::ALL_EVENT_TYPES)
    end

    def stream = JSON.parse(request(Net::HTTP::Get, "stream").body)

    # Asks Google to send a verification event with this state.
    def verify(state) = post("stream:verify", state: state)

    # "enabled" or "disabled".
    def update_status(status) = post("stream/status:update", status: status)

    private

    def post(path, body) = request(Net::HTTP::Post, path, body)

    def request(method, path, body = nil)
      uri = URI.parse("#{BASE_URL}#{path}")
      request = method.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: Validator::OPEN_TIMEOUT, read_timeout: Validator::READ_TIMEOUT) do |http|
        http.request(request)
      end
      raise Error, "#{response.code} #{response.message}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    # A self-signed JWT of the service account, valid for one hour.
    def auth_token
      issued_at = Time.current.to_i
      payload = {
        iss: @credentials["client_email"],
        sub: @credentials["client_email"],
        aud: TOKEN_AUDIENCE,
        iat: issued_at,
        exp: issued_at + 1.hour.to_i
      }

      JWT.encode(payload, OpenSSL::PKey::RSA.new(@credentials["private_key"]), "RS256",
                 kid: @credentials["private_key_id"])
    end
  end
end
