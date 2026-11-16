# frozen_string_literal: true

module Sources
  # Loads the CatalogCourse of many sections in one query. Keys are
  # [subject_code, course_number].
  class CatalogCourseSource < GraphQL::Dataloader::Source
    def fetch(keys)
      found = CatalogCourse.by_codes(keys).index_by { |course| [ course.subject_code, course.course_number ] }
      keys.map { |key| found[key] }
    end
  end
end
