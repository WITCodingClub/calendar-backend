# frozen_string_literal: true

module DegreeRequirements
  # Where one catalog year can be read: the current catalog site, its archive
  # under /previous-catalogs/, or a Wayback Machine copy. Links on every one
  # of them are site paths, so url_for puts the right prefix in front.
  class CatalogSource
    KINDS = %i[archive current wayback].freeze

    # Each page of the catalog ends with "Boston, MA 2024-2025". The import
    # checks it, because the current site moves to a new year in the summer,
    # and a Wayback capture can be from the year before.
    YEAR_MARK = /Boston,\s*MA\s+(\d{4})-\d{4}/

    attr_reader :start_year, :kind, :index_html

    def self.page_start_year(html)
      html.to_s[YEAR_MARK, 1]&.to_i
    end

    # The source for a catalog year, or nil when no source has it. It reads
    # the program index of each place in turn, and keeps the page it found.
    def self.locate(start_year, client:)
      candidates = [ new(start_year, :archive), new(start_year, :current) ]
      candidates << new(start_year, :wayback) if WAYBACK_TIMESTAMPS.key?(start_year)

      candidates.each do |source|
        html = client.get(source.index_url)
        return source.with_index(html) if html && page_start_year(html) == start_year
      end
      nil
    end

    def initialize(start_year, kind)
      raise ArgumentError, "unknown source #{kind}" unless KINDS.include?(kind)

      @start_year = start_year
      @kind = kind
    end

    def with_index(html)
      @index_html = html
      self
    end

    # The value for CatalogYear#source.
    def catalog_year_source = wayback? ? "wayback" : "html"

    def wayback? = kind == :wayback

    def year_span = "#{start_year}-#{start_year + 1}"

    # The site path the catalog year starts at: "/previous-catalogs/2024-2025/" or "/".
    def home_path = kind == :archive ? "/previous-catalogs/#{year_span}/" : "/"

    def index_url = url_for("#{home_path}programs-az/")

    def base_url = url_for(home_path)

    def url_for(path)
      prefix = wayback? ? "https://web.archive.org/web/#{WAYBACK_TIMESTAMPS.fetch(start_year)}id_/#{SITE_URL}" : SITE_URL
      "#{prefix}#{path}"
    end
  end
end
