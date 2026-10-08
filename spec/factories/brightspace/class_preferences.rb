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
FactoryBot.define do
  factory :brightspace_class_preference, class: "Brightspace::ClassPreference" do
    association :course_offering, factory: :brightspace_course_offering
    user { course_offering.connection.user }
    sync_enabled { true }
  end
end
