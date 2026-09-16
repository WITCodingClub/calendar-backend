# frozen_string_literal: true

require "faraday/retry"

module MicrosoftGraph
  # A small JSON client for Microsoft Graph v1.0 that acts as one person.
  #
  # It refreshes the access token before a request when the token is about to
  # expire, and once more when Graph answers 401.
  class Client
    BASE_URL     = "https://graph.microsoft.com/v1.0"
    TIME_ZONE    = "Eastern Standard Time"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20

    RETRY_OPTIONS = {
      max:            2,
      interval:       1,
      backoff_factor: 2,
      retry_statuses: [ 429, 503, 504 ],
      methods:        %i[get patch delete]
    }.freeze

    attr_reader :credential

    def initialize(credential, token_client: TokenClient.new)
      raise AuthError, "no Microsoft credential" unless credential

      @credential   = credential
      @token_client = token_client
    end

    def get(path, params: {})
      request(:get, path, params: params)
    end

    def post(path, body)
      request(:post, path, body: body)
    end

    def patch(path, body)
      request(:patch, path, body: body)
    end

    def delete(path)
      request(:delete, path)
    end

    private

    attr_reader :token_client

    def request(method, path, params: {}, body: nil, retried: false)
      token_client.refresh!(credential) if credential.token_expired?

      response = connection.run_request(method, "#{BASE_URL}/#{path}", body&.to_json, headers) do |req|
        req.params.update(params) if params.any?
      end

      if response.status == 401 && !retried
        token_client.refresh!(credential)
        return request(method, path, params: params, body: body, retried: true)
      end

      handle(method, path, response)
    end

    def handle(method, path, response)
      return parse(response.body) if response.success?

      error_class = response.status == 404 ? NotFoundError : Error
      raise error_class.new("Graph #{method.to_s.upcase} #{path.split('?').first} returned #{response.status}",
                            status: response.status, body: parse(response.body))
    end

    def headers
      {
        "Authorization" => "Bearer #{credential.access_token}",
        "Content-Type"  => "application/json",
        "Accept"        => "application/json",
        "Prefer"        => %(outlook.timezone="#{TIME_ZONE}")
      }
    end

    def parse(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def connection
      @connection ||= Faraday.new(request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT }) do |f|
        f.request :retry, RETRY_OPTIONS
      end
    end
  end
end
