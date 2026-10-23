# frozen_string_literal: true

module DegreeRequirements
  # The JSON API behind the catalog's course search (CourseLeaf "FOSE"). It
  # has the courses of each catalog year from 2019-2020. `srcdb` is the first
  # year of the catalog year, such as "2025" for 2025-2026.
  class CourseSearchClient
    require "faraday"
    require "faraday/retry"

    URL = "#{SITE_URL}/course-search/api/".freeze

    def initialize(delay: 0.25)
      @pacer = RequestPacer.new(delay)
    end

    # Every course of a catalog year: [{ "code" => "COMP2350", "title" => "ALGORITHMS" }, ...].
    # An empty list when the year has no course search data.
    def search(start_year)
      body = post("search", { other: { srcdb: start_year.to_s }, criteria: [] })
      body.is_a?(Hash) ? Array(body["results"]) : []
    end

    # One course: { "code", "title", "description" }, or nil when the year
    # does not have it.
    def details(start_year, code)
      body = post("details", { group: "code:#{code}", key: "", srcdb: start_year.to_s, matched: "" })
      body.is_a?(Hash) && body["code"].present? ? body : nil
    end

    private

    def post(route, payload)
      @pacer.wait
      response = connection.post("?page=fose&route=#{route}", payload.to_json)
      raise FetchError, "course search #{route}: HTTP #{response.status}" unless response.success?

      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError => e
      raise FetchError, "course search #{route}: #{e.message}"
    rescue Faraday::Error => e
      raise FetchError, "course search #{route}: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: URL, request: { open_timeout: 10, timeout: 30 }) do |f|
        f.request :retry, CatalogSiteClient::RETRY_OPTIONS.merge(methods: %i[post])
        f.headers["User-Agent"] = USER_AGENT
        f.headers["Content-Type"] = "application/json"
      end
    end
  end
end
