# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_class_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  grade_categories     :jsonb
#  grade_mode           :string
#  included_kinds       :string           is an Array
#  location_template    :text
#  reminder_settings    :jsonb
#  sync_enabled         :boolean
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :string
#  course_offering_id   :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_brightspace_class_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_class_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  # The user's settings for one class. A nil calendar field inherits the
  # calendar preferences, the same way as event preferences.
  class ClassPreferenceSerializer
    include PreferenceSerializable

    def initialize(preference)
      @preference = preference
    end

    def as_json(*)
      preference = @preference || Brightspace::ClassPreference.new

      {
        calendar: {
          sync_enabled:         preference.effective_sync_enabled,
          included_kinds:       preference.effective_included_kinds,
          title_template:       preference.title_template,
          description_template: preference.description_template,
          location_template:    preference.location_template,
          color_id:             preference.color_id,
          visibility:           preference.visibility,
          reminder_settings:    transform_reminder_settings(preference.reminder_settings)
        },
        grades: {
          mode:       preference.effective_grade_mode,
          categories: preference.grade_categories || []
        }
      }
    end
  end
end
