# frozen_string_literal: true

module Sources
  # Loads the CatalogCourse of many sections in one query. Keys are
  # [subject_code, course_number].
  class CatalogCourseSource < GraphQL::Dataloader::Source
    def fetch(keys)
      pairs = keys.uniq
      conditions = pairs.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
      found = CatalogCourse.where(conditions, *pairs.flatten).index_by { |course| [ course.subject_code, course.course_number ] }
      keys.map { |key| found[key] }
    end
  end
end
