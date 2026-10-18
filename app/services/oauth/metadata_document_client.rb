# frozen_string_literal: true

require "resolv"

module Oauth
  # Fetches a client ID metadata document from the client's own server.
  #
  # The URL comes from a stranger, so the request is guarded against SSRF:
  #
  # - HTTPS on port 443 only.
  # - Every address the host resolves to must be public. The connection then
  #   goes to the address that was checked, so a second DNS answer cannot
  #   point it inside the network.
  # - No redirects, a short timeout, and a small body limit.
  class MetadataDocumentClient
    TIMEOUT   = 5
    MAX_BYTES = 10_240

    # Addresses that a public client server never has.
    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
      192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    class FetchError < StandardError; end

    # @return [Hash] the parsed JSON object
    def fetch(uri)
      raise FetchError, "the client id must use https on port 443" unless uri.scheme == "https" && uri.port == 443

      code, body = request(uri, public_address(uri.host))
      raise FetchError, "the client metadata document answered #{code}" unless code == "200"

      document = JSON.parse(body)
      raise FetchError, "the client metadata document is not a JSON object" unless document.is_a?(Hash)

      document
    rescue JSON::ParserError
      raise FetchError, "the client metadata document is not valid JSON"
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Net::HTTPBadResponse => e
      raise FetchError, "could not fetch the client metadata document (#{e.class.name})"
    end

    def self.blocked?(address)
      ip = IPAddr.new(address)
      ip = ip.native if ip.ipv4_mapped?
      BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    private

    def public_address(host)
      addresses = Resolv.getaddresses(host)
      raise FetchError, "the client id host does not resolve" if addresses.empty?
      raise FetchError, "the client id host is not a public address" if addresses.any? { |address| self.class.blocked?(address) }

      addresses.first
    end

    def request(uri, address)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = true
      http.ipaddr        = address
      http.open_timeout  = TIMEOUT
      http.read_timeout  = TIMEOUT
      http.write_timeout = TIMEOUT

      http.start do
        get = Net::HTTP::Get.new(uri.request_uri, "Accept" => "application/json")
        http.request(get) { |response| return [ response.code, read_limited(response) ] }
      end
    end

    def read_limited(response)
      body = +""
      response.read_body do |chunk|
        body << chunk
        raise FetchError, "the client metadata document is larger than #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
      end
      body
    end
  end
end
