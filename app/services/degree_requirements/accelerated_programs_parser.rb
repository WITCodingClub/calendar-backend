# frozen_string_literal: true

module DegreeRequirements
  # Reads the Accelerated Programs page of the current catalog
  # (/programs-az/accelerated-programs/). Each paragraph names one option. A
  # paragraph with one link is a 3-year plan of a B.S., which the program
  # page already has as an accelerated plan. A paragraph with two or more
  # links is a pathway through those programs, such as "Architecture, B.S.
  # and Master of Architecture 5-Year".
  class AcceleratedProgramsParser
    require "nokogiri"

    PATH = "/programs-az/accelerated-programs/"

    Entry = Data.define(:name, :slugs)

    def initialize(html)
      @doc = Nokogiri::HTML(html)
    end

    # The paragraphs with two or more program links, in page order.
    def entries
      @doc.css("#textcontainer p").filter_map do |paragraph|
        slugs = paragraph.css("a[href]").filter_map { |link| program_slug(link["href"]) }.uniq
        next if slugs.size < 2

        Entry.new(name: paragraph.text.squish, slugs: slugs)
      end
    end

    private

    # The last part of a catalog site path, such as "architecture-bs". nil
    # for a link to another site or to a part of this page.
    def program_slug(href)
      uri = URI.parse(href.to_s)
      return nil if uri.host.present? && uri.host != URI(SITE_URL).host
      return nil unless uri.path.to_s.start_with?("/")

      DegreeProgram.slug_for_path(uri.path)
    rescue URI::InvalidURIError
      nil
    end
  end
end
