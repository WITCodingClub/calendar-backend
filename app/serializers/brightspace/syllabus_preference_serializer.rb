# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_syllabus_preferences
#
#  id                 :bigint           not null, primary key
#  confirmed          :jsonb            not null
#  source_revision    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_brightspace_syllabus_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_syllabus_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  class SyllabusPreferenceSerializer
    def initialize(preference)
      @preference = preference
    end

    def as_json(*)
      return nil if @preference.nil?

      {
        source_revision: @preference.source_revision,
        confirmed:       @preference.confirmed,
        confirmed_at:    @preference.updated_at&.utc&.iso8601
      }
    end
  end
end
