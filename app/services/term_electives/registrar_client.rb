# frozen_string_literal: true

module TermElectives
  # Fetches the Registrar's elective page and the PDFs it links. It only
  # follows a redirect to wit.edu over HTTPS.
  class RegistrarClient
    require "faraday"
    require "faraday/retry"

    RETRY_OPTIONS = {
      max:            3,
      interval:       2,
      backoff_factor: 2,
      retry_statuses: [ 429, 502, 503, 504 ],
      methods:        %i[get]
    }.freeze
    MAX_REDIRECTS = 3
    # The lists are a few pages. A larger file is not an elective list.
    MAX_BYTES = 20.megabytes
    ALLOWED_HOSTS = [ SITE_HOST, "www.#{SITE_HOST}" ].freeze

    # The body as binary, or nil for a 404. Raises FetchError for any other
    # failure.
    def get(url)
      MAX_REDIRECTS.succ.times do
        response = connection.get(url)
        return nil if response.status == 404

        if response.status.in?(300..399) && response.headers["location"].present?
          url = redirect_target(url, response.headers["location"])
          next
        end
        raise FetchError, "GET #{url}: HTTP #{response.status}" unless response.success?

        body = response.body.to_s.b
        raise FetchError, "GET #{url}: larger than #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES

        return body
      end
      raise FetchError, "GET #{url}: too many redirects"
    rescue Faraday::Error => e
      raise FetchError, "GET #{url}: #{e.message}"
    end

    private

    def redirect_target(from, location)
      target = begin
        URI.join(from, location)
      rescue URI::Error
        raise FetchError, "GET #{from}: bad redirect to #{location}"
      end
      unless target.scheme == "https" && target.host.to_s.downcase.in?(ALLOWED_HOSTS)
        raise FetchError, "GET #{from}: redirect to #{target.host || location} is not allowed"
      end

      target.to_s
    end

    def connection
      @connection ||= Faraday.new(request: { open_timeout: 10, timeout: 30 }) do |f|
        f.request :retry, RETRY_OPTIONS
        f.headers["User-Agent"] = USER_AGENT
      end
    end
  end
end
