# frozen_string_literal: true

module DegreeRequirements
  # Fetches pages of the catalog site, of a Wayback Machine copy, or the
  # Double Leopard page on wit.edu. It waits `delay` seconds between
  # requests, so an import of a whole year does not load either site.
  class CatalogSiteClient
    # The Wayback Machine refuses connections from a client that asks for
    # more than about 15 pages a minute.
    WAYBACK_HOST = "web.archive.org"
    WAYBACK_DELAY = 5
    ALLOWED_HOSTS = [ URI(SITE_URL).host, WAYBACK_HOST, URI(DOUBLE_LEOPARD_URL).host, "www.wit.edu" ].freeze

    def initialize(delay: 0.5, wayback_delay: WAYBACK_DELAY)
      @pacer = RequestPacer.new(delay)
      @wayback_pacer = RequestPacer.new(wayback_delay)
    end

    # The page body, or nil for a 404. Raises FetchError for any other failure.
    # It follows redirects: the Wayback Machine sends each request on to the
    # nearest capture. With binary: true the body is returned as bytes, for
    # a PDF.
    def get(url, binary: false)
      body = fetcher.get(url)
      return body if body.nil? || binary

      # A stray byte from another encoding would make every regex on the page
      # raise, so it is replaced.
      body.force_encoding(Encoding::UTF_8).scrub
    end

    private

    def fetcher
      # A catalog PDF is about 5 MB.
      @fetcher ||= HttpFetcher.new(
        allowed_hosts:  ALLOWED_HOSTS,
        error:          FetchError,
        timeout:        60,
        before_request: ->(url) { (URI(url).host == WAYBACK_HOST ? @wayback_pacer : @pacer).wait }
      )
    end
  end
end
