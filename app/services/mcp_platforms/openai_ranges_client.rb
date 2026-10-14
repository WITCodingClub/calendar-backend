# frozen_string_literal: true

module McpPlatforms
  # Reads the egress ranges that OpenAI publishes for ChatGPT connectors.
  class OpenaiRangesClient
    URL          = "https://openai.com/chatgpt-connectors.json"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # A published range wider than this would cover far more than one
    # company's servers, so a list that has one is refused.
    MIN_IPV4_PREFIX = 16
    MIN_IPV6_PREFIX = 32

    class Error < StandardError; end

    # @return [Array<String>] CIDR ranges
    def fetch
      response = connection.get(URL)
      raise Error, "OpenAI answered #{response.status}" unless response.status == 200

      prefixes = Array(response.body.is_a?(Hash) ? response.body["prefixes"] : nil)
      ranges   = prefixes.filter_map { |prefix| prefix["ipv4Prefix"] || prefix["ipv6Prefix"] if prefix.is_a?(Hash) }
      raise Error, "the OpenAI list has no prefixes" if ranges.empty?

      ranges.each { |range| check!(range) }
      ranges
    rescue Faraday::Error => e
      raise Error, "could not fetch the OpenAI list (#{e.class.name})"
    end

    private

    def check!(range)
      ip     = IPAddr.new(range)
      prefix = ip.prefix
      too_wide = ip.ipv4? ? prefix < MIN_IPV4_PREFIX : prefix < MIN_IPV6_PREFIX
      raise Error, "the OpenAI list has a range that is too wide: #{range}" if too_wide
    rescue IPAddr::InvalidAddressError
      raise Error, "the OpenAI list has an invalid range: #{range.to_s.first(50)}"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout      = READ_TIMEOUT
        # OpenAI serves the file as application/octet-stream, so parse every
        # body, not only one with a JSON content type.
        f.response :json, content_type: //
      end
    end
  end
end
