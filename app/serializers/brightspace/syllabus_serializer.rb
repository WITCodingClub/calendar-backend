# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_syllabi
#
#  id                 :bigint           not null, primary key
#  extracted          :jsonb            not null
#  removed_at         :datetime
#  revision           :string           not null
#  source_url         :string
#  title              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string
#
# Indexes
#
#  index_brightspace_syllabi_on_course_offering_id  (course_offering_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
module Brightspace
  # The syllabus source, the rules that the extension read from it, and the
  # rules that the user confirmed. The confirmed rules are private to the user.
  class SyllabusSerializer
    def initialize(offering)
      @offering = offering
    end

    def as_json(*)
      syllabus = @offering.syllabus

      {
        source:    syllabus && {
          source_id:  syllabus.source_id,
          url:        syllabus.source_url,
          title:      syllabus.title,
          revision:   syllabus.revision,
          removed_at: syllabus.removed_at&.utc&.iso8601
        },
        extracted: syllabus&.extracted,
        confirmed: SyllabusPreferenceSerializer.new(@offering.syllabus_preference).as_json,
        version:   @offering.version
      }
    end
  end
end
