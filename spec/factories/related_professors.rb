# frozen_string_literal: true

# == Schema Information
#
# Table name: related_professors
#
#  id                 :bigint           not null, primary key
#  avg_rating         :decimal(3, 2)
#  first_name         :string
#  last_name          :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  faculty_id         :bigint           not null
#  related_faculty_id :bigint
#  rmp_id             :string           not null
#
# Indexes
#
#  index_related_professors_on_faculty_id             (faculty_id)
#  index_related_professors_on_faculty_id_and_rmp_id  (faculty_id,rmp_id) UNIQUE
#  index_related_professors_on_related_faculty_id     (related_faculty_id)
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#  fk_rails_...  (related_faculty_id => faculties.id)
#
FactoryBot.define do
  factory :related_professor do
    association :faculty
    sequence(:rmp_id) { |n| "factory-related-rmp-#{n}" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
  end
end
