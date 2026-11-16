# frozen_string_literal: true

# Fetches pages and files from the outside sites that the app reads: wit.edu,
# catalog.wit.edu, the Wayback Machine, the faculty directory and photos, the
# university calendar feed, 25Live, the OpenAI address list, GitHub releases,
# and the Google RISC keys. They all send one user agent and retry the same
# way.
#
# Outside it: the RateMyProfessors client sends the headers of the
# RateMyProfessors site, LeopardWebClient keeps a Banner session, the OAuth
# token calls use OauthCredentials::Http, and Oauth::MetadataDocumentClient
# checks every address it connects to.
class HttpFetcher
  require "faraday"
  require "faraday/retry"

  USER_AGENT = "WITCalendarBot/1.0"

  # A busy or restarting server answers with one of these statuses, or drops
  # the connection. A request is sent again only when it changes nothing (GET
  # by default).
  RETRY_OPTIONS = {
    max:            3,
    interval:       2,
    backoff_factor: 2,
    exceptions:     [ *Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS, Faraday::ConnectionFailed ],
    retry_statuses: [ 429, 502, 503, 504 ],
    methods:        %i[get]
  }.freeze

  MAX_REDIRECTS = 3
  OPEN_TIMEOUT = 10

  # A Faraday connection with the user agent, the timeouts, and the retry
  # policy. The block adds more middleware, such as a JSON encoder. A request
  # that runs while a page renders passes short timeouts and
  # retry_methods: [], so a slow site cannot hold the page for the retries.
  def self.connection(url: nil, timeout: 30, open_timeout: OPEN_TIMEOUT, retry_methods: %i[get])
    Faraday.new(url: url, request: { open_timeout: open_timeout, timeout: timeout }) do |f|
      f.request :retry, RETRY_OPTIONS.merge(methods: retry_methods)
      f.headers["User-Agent"] = USER_AGENT
      yield f if block_given?
    end
  end

  # allowed_hosts: the hosts a redirect may go to, over HTTPS only, so a bad
  # redirect cannot send the server to another host.
  # error: the error class to raise, so the job of each domain retries its own.
  # before_request: called with each URL before it is requested, for pacing.
  # connection_options: the timeouts and retry_methods of HttpFetcher.connection.
  def initialize(allowed_hosts:, error:, before_request: nil, **connection_options)
    @allowed_hosts  = allowed_hosts.map(&:downcase)
    @error          = error
    @connection_options = connection_options
    @before_request = before_request
  end

  # The body as bytes, or nil for a 404. It follows redirects. Raises the error
  # class for any other failure, and for a body larger than max_bytes.
  def get(url, max_bytes: nil)
    MAX_REDIRECTS.succ.times do
      @before_request&.call(url)
      response = connection.get(url)
      return nil if response.status == 404

      if response.status.in?(300..399) && response.headers["location"].present?
        url = redirect_target(url, response.headers["location"])
        next
      end
      raise @error, "GET #{url}: HTTP #{response.status}" unless response.success?

      body = response.body.to_s.b
      raise @error, "GET #{url}: larger than #{max_bytes} bytes" if max_bytes && body.bytesize > max_bytes

      return body
    end
    raise @error, "GET #{url}: too many redirects"
  rescue Faraday::Error => e
    raise @error, "GET #{url}: #{e.message}"
  end

  private

  def redirect_target(from, location)
    target = begin
      URI.join(from, location)
    rescue URI::Error
      raise @error, "GET #{from}: bad redirect to #{location}"
    end
    unless target.scheme == "https" && target.host.to_s.downcase.in?(@allowed_hosts)
      raise @error, "GET #{from}: redirect to #{target.host || location} is not allowed"
    end

    target.to_s
  end

  def connection
    @connection ||= self.class.connection(**@connection_options)
  end
end
