# frozen_string_literal: true

# The addresses that hosted MCP clients send their requests from.
#
# claude.ai and ChatGPT call the MCP server from their own servers, so every
# student who uses one of them shares a few IP addresses. Rack::Attack does
# not apply its per-IP limits to these addresses. It applies the per-user
# limits instead, because each MCP request carries the user's token, and one
# high limit for each address as a backstop.
#
# - Anthropic publishes one fixed range, which does not change without notice:
#   https://platform.claude.com/docs/en/api/ip-addresses
# - OpenAI publishes a list that changes:
#   https://openai.com/chatgpt-connectors.json. McpPlatforms::RefreshOpenaiRangesJob
#   keeps a copy in Rails.cache. Without a copy, ChatGPT gets the normal
#   per-IP limits, which is safe.
module McpPlatforms
  ANTHROPIC_RANGES = %w[160.79.104.0/21].freeze

  OPENAI_CACHE_KEY = "mcp_platforms/openai_ranges"
  # A copy stays for a week, so a few failed refreshes change nothing.
  OPENAI_CACHE_TTL = 7.days

  # Rack::Attack asks on every request, and Rails.cache is a database read,
  # so each process keeps the list in memory for a short time.
  MEMO_TTL = 10.minutes

  def self.include?(address)
    return false if address.blank?

    ip = IPAddr.new(address)
    ranges.any? { |range| range.family == ip.family && range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end

  def self.ranges
    # reset! can run on another thread, so read the ivar once.
    ranges = @ranges
    if ranges.nil? || @ranges_loaded_at < MEMO_TTL.ago
      ranges = (ANTHROPIC_RANGES + Array(Rails.cache.read(OPENAI_CACHE_KEY))).map { |range| IPAddr.new(range) }.freeze
      @ranges_loaded_at = Time.current
      @ranges = ranges
    end

    ranges
  end

  def self.store_openai_ranges(prefixes)
    Rails.cache.write(OPENAI_CACHE_KEY, prefixes, expires_in: OPENAI_CACHE_TTL)
    reset!
  end

  def self.reset!
    @ranges = nil
  end
end
