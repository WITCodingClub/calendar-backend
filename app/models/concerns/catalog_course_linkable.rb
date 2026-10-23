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
  end

  class_methods do
    # Links each row with no catalog course to the CatalogCourse with its
    # code. Returns the number of rows it linked.
    def link_catalog_courses
      match = <<~SQL.squish
        FROM catalog_courses
        WHERE catalog_courses.subject_code = #{table_name}.subject_code
          AND catalog_courses.course_number = #{table_name}.course_number
      SQL

      where(catalog_course_id: nil)
        .where("EXISTS (SELECT 1 #{match})")
        .update_all("catalog_course_id = (SELECT catalog_courses.id #{match})")
    end
  end

  def code
    "#{subject_code} #{course_number}" if subject_code && course_number
  end
end
