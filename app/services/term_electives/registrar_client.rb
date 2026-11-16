# frozen_string_literal: true

module TermElectives
  # Fetches the Registrar's elective page and the PDFs it links. It only
  # follows a redirect to wit.edu over HTTPS.
  class RegistrarClient
    # The lists are a few pages. A larger file is not an elective list.
    MAX_BYTES = 20.megabytes
    ALLOWED_HOSTS = [ SITE_HOST, "www.#{SITE_HOST}" ].freeze

    # The body as binary, or nil for a 404. Raises FetchError for any other
    # failure.
    def get(url)
      fetcher.get(url, max_bytes: MAX_BYTES)
    end

    private

    def fetcher
      @fetcher ||= HttpFetcher.new(allowed_hosts: ALLOWED_HOSTS, error: FetchError)
    end
  end
end
