# frozen_string_literal: true

# A row that names a course by subject code and number, such as COMP 2350,
# and links to the CatalogCourse with that code. The link is nil for a code
# that Banner does not know. The importer sets the links in bulk with
# link_catalog_courses.
module CatalogCourseLinkable
  extend ActiveSupport::Concern

  included do
    belongs_to :catalog_course, optional: true

    before_validation { self.subject_code = subject_code&.strip&.upcase.presence }
    # A new code makes the old link wrong. link_catalog_courses sets it again.
    before_save do
      self.catalog_course_id = nil if will_save_change_to_subject_code? || will_save_change_to_course_number?
    end
  end

  class_methods do
    # Sets each row's link to the CatalogCourse with its code, and clears a
    # link that names another course, such as after a bulk write changed
    # the code. Returns the number of rows it changed.
    def link_catalog_courses
      matching_id = <<~SQL.squish
        (SELECT catalog_courses.id FROM catalog_courses
         WHERE catalog_courses.subject_code = #{table_name}.subject_code
           AND catalog_courses.course_number = #{table_name}.course_number)
      SQL

      where("#{table_name}.catalog_course_id IS DISTINCT FROM #{matching_id}")
        .update_all("catalog_course_id = #{matching_id}")
    end
  end

  def code
    "#{subject_code} #{course_number}" if subject_code && course_number
  end
end
