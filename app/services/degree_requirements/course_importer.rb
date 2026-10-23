# frozen_string_literal: true

module DegreeRequirements
  # Imports the courses of one catalog year from the course search into
  # CatalogYearCourse: one request for the list, then one for each course.
  # The course search starts with 2019-2020, so an older year imports none.
  class CourseImporter
    BATCH_SIZE = 200

    def initialize(catalog_year, client: CourseSearchClient.new)
      @catalog_year = catalog_year
      @client = client
    end

    # The number of courses written.
    def call
      results = @client.search(@catalog_year.start_year)
      rows = results.filter_map { |result| row_for(result) }.uniq { |row| row.values_at(:subject_code, :course_number) }

      rows.each_slice(BATCH_SIZE) do |batch|
        CatalogYearCourse.upsert_all(batch, unique_by: :idx_catalog_year_courses_unique,
                                            update_only: %i[title description min_credits max_credits
                                                            prerequisite_text typically_offered])
      end
      CatalogYearCourse.link_catalog_courses

      Rails.logger.info("[DegreeRequirements::CourseImporter] #{@catalog_year.name}: #{rows.size} courses")
      rows.size
    end

    private

    def row_for(result)
      subject_code, course_number = CatalogCourse.parse_code(result["code"])
      return nil if subject_code.nil?

      details = fetch_details(result["code"])
      parsed = CourseDescriptionParser.call(details&.dig("description"))
      { catalog_year_id: @catalog_year.id, subject_code: subject_code, course_number: course_number,
        title: CGI.unescapeHTML((details&.dig("title") || result["title"]).to_s).strip.presence,
        description: parsed.description, prerequisite_text: parsed.prerequisite_text,
        min_credits: parsed.min_credits, max_credits: parsed.max_credits,
        typically_offered: parsed.typically_offered }
    end

    # One course that fails keeps its title from the list, so the rest of the
    # year still imports.
    def fetch_details(code)
      @client.details(@catalog_year.start_year, code)
    rescue FetchError => e
      Rails.error.report(e, handled: true, context: { catalog_year_id: @catalog_year.id, code: code })
      nil
    end
  end
end
