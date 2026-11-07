# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Saves the title and credits of each course in the plans of a PDF year
    # as a CatalogYearCourse. The course search API starts at 2019-2020, so
    # for older years the plans are the only source. AliasFinder compares
    # these titles between 2014-2015 and 2015-2016.
    #
    # A row that exists keeps its values: the first plan that names a course
    # sets them, and a title that differs in another plan is a typo there.
    module CatalogYearCourses
      module_function

      def call(catalog_year, plans)
        now = Time.current
        rows = plans.flat_map(&:items).select { |item| item.kind == "course" && item.label.present? }
                    .uniq { |item| [ item.subject_code, item.course_number ] }
                    .map do |item|
          { catalog_year_id: catalog_year.id, subject_code: item.subject_code, course_number: item.course_number,
            title: item.label.truncate(255), min_credits: item.min_credits, max_credits: item.max_credits,
            created_at: now, updated_at: now }
        end
        return 0 if rows.empty?

        inserted = CatalogYearCourse.insert_all(rows, unique_by: :idx_catalog_year_courses_unique).length
        CatalogYearCourse.link_catalog_courses
        inserted
      end
    end
  end
end
