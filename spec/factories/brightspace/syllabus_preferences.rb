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
FactoryBot.define do
  factory :brightspace_syllabus_preference, class: "Brightspace::SyllabusPreference" do
    association :course_offering, factory: :brightspace_course_offering
    user { course_offering.connection.user }
    source_revision { "rev-1" }
    confirmed { { "categories" => [ { "name" => "Labs", "weight" => 40 } ] } }
  end
end
