# frozen_string_literal: true

module DegreeRequirements
  # Fetches pages of the catalog site or of a Wayback Machine copy. It waits
  # `delay` seconds between requests, so an import of a whole year does not
  # load either site.
  class CatalogSiteClient
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

    # The Wayback Machine refuses connections from a client that asks for
    # more than about 15 pages a minute.
    WAYBACK_HOST = "web.archive.org"
    WAYBACK_DELAY = 5

    def initialize(delay: 0.5, wayback_delay: WAYBACK_DELAY)
      @pacer = RequestPacer.new(delay)
      @wayback_pacer = RequestPacer.new(wayback_delay)
    end

    # The page body, or nil for a 404. Raises FetchError for any other failure.
    # It follows redirects: the Wayback Machine sends each request on to the
    # nearest capture.
    def get(url)
      MAX_REDIRECTS.succ.times do
        (URI(url).host == WAYBACK_HOST ? @wayback_pacer : @pacer).wait
        response = connection.get(url)
        return nil if response.status == 404

        if response.status.in?(300..399) && response.headers["location"].present?
          url = URI.join(url, response.headers["location"]).to_s
          next
        end
        raise FetchError, "GET #{url}: HTTP #{response.status}" unless response.success?

        return response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      end
      raise FetchError, "GET #{url}: too many redirects"
    rescue Faraday::Error => e
      raise FetchError, "GET #{url}: #{e.message}"
    end

    private

    def connection
      @connection ||= Faraday.new(request: { open_timeout: 10, timeout: 30 }) do |f|
        f.request :retry, RETRY_OPTIONS
        f.headers["User-Agent"] = USER_AGENT
      end
    end
  end
end
