# frozen_string_literal: true

module OauthCredentials
  # The HTTP connection of the calls to Google and Microsoft that check,
  # trade, refresh, or revoke a token, and of the Graph client. A request
  # waits at most a few seconds, because it holds a web request or a worker
  # thread.
  module Http
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # The errors of a request that did not get an answer.
    NETWORK_ERRORS = [ Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError ].freeze

    module_function

    def connection(read_timeout: READ_TIMEOUT, &)
      Faraday.new(request: { open_timeout: OPEN_TIMEOUT, timeout: read_timeout }, &)
    end

    # Posts params as a form, the format of every OAuth token endpoint.
    def post_form(url, params, read_timeout: READ_TIMEOUT)
      connection(read_timeout: read_timeout).post(url) do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(params)
      end
    end

    # The JSON body as a Hash. An empty or broken body is an empty Hash, so a
    # caller reads a missing field, not a parse error.
    def parse(body)
      return body if body.is_a?(Hash)
      return {} if body.blank?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
