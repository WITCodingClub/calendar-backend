# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_course_offerings
#
#  id             :bigint           not null, primary key
#  data_version   :integer          default(1), not null
#  reported_total :jsonb
#  sections       :jsonb            not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  connection_id  :bigint           not null
#  course_id      :bigint
#  source_id      :string           not null
#  term_id        :bigint
#
# Indexes
#
#  idx_on_connection_id_source_id_cec08f631c            (connection_id,source_id) UNIQUE
#  index_brightspace_course_offerings_on_connection_id  (connection_id)
#  index_brightspace_course_offerings_on_course_id      (course_id)
#  index_brightspace_course_offerings_on_term_id        (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (connection_id => brightspace_connections.id)
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :brightspace_course_offering, class: "Brightspace::CourseOffering" do
    association :connection, factory: :brightspace_connection
    sequence(:source_id) { |n| (12_000 + n).to_s }
    title { Faker::Educator.course_name }

    trait :with_course do
      course { association :course }
      term { course.term }
    end
  end
end
