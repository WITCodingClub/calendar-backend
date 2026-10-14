# frozen_string_literal: true

module Oauth
  # Rules for the redirect URIs that MCP clients register.
  #
  # A hosted client (claude.ai, ChatGPT) uses HTTPS. A local client (Claude
  # Code, the MCP Inspector) runs a server on the loopback address, so plain
  # HTTP is allowed for localhost and 127.0.0.1 only. RFC 8252 section 7.3
  # describes loopback redirects.
  module RedirectUris
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1] ::1].freeze
    MAX_COUNT      = 10
    MAX_LENGTH     = 2_000

    module_function

    # The hosts in a newline-separated list of redirect URIs, for the consent
    # page and Settings.
    def hosts(redirect_uri)
      redirect_uri.to_s.split.filter_map do |value|
        URI.parse(value).host
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    def loopback?(uri)
      LOOPBACK_HOSTS.include?(uri.host.to_s.downcase)
    end

    # Returns an error message, or nil when every URI is acceptable.
    def error_for(uris)
      return "redirect_uris must be a non-empty array" unless uris.is_a?(Array) && uris.any?
      return "too many redirect_uris (at most #{MAX_COUNT})" if uris.size > MAX_COUNT

      uris.each do |value|
        message = error_for_one(value)
        return message if message
      end

      nil
    end

    def error_for_one(value)
      return "each redirect URI must be a string" unless value.is_a?(String)
      return "redirect URI is too long" if value.length > MAX_LENGTH

      uri = URI.parse(value)
      return "redirect URI must be absolute: #{value}" unless uri.host.present?
      return "redirect URI must not have a fragment: #{value}" if uri.fragment
      return "redirect URI must not have user info: #{value}" if uri.userinfo
      return nil if uri.scheme == "https"
      return nil if uri.scheme == "http" && loopback?(uri)

      "redirect URI must use https, or http on a loopback address: #{value}"
    rescue URI::InvalidURIError
      "redirect URI is not a valid URI: #{value}"
    end
  end
end
