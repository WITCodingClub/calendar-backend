# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
#  employee_type            :string
#  first_name               :string           not null
#  last_name                :string           not null
#  middle_name              :string
#  office_location          :string
#  phone                    :string
#  photo_url                :string
#  rmp_raw_data             :jsonb
#  school                   :string
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  rmp_id                   :string
#
# Indexes
#
#  index_faculties_on_department                (department)
#  index_faculties_on_directory_last_synced_at  (directory_last_synced_at)
#  index_faculties_on_directory_raw_data        (directory_raw_data) USING gin
#  index_faculties_on_email                     (email) UNIQUE
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
FactoryBot.define do
  factory :faculty do
    sequence(:first_name) { |n| "Professor#{n}" }
    sequence(:last_name) { |n| "Faculty#{n}" }
    sequence(:email) { |n| "faculty#{n}@witcc.edu" }
    rmp_id { nil }
    rmp_raw_data { {} }
  end
end
