# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id           :bigint           not null, primary key
#  email        :string           not null
#  embedding    :vector(1536)
#  first_name   :string           not null
#  last_name    :string           not null
#  rmp_raw_data :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  rmp_id       :string
#
# Indexes
#
#  index_faculties_on_email         (email) UNIQUE
#  index_faculties_on_rmp_id        (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data  (rmp_raw_data) USING gin
#
FactoryBot.define do
  factory :faculty do
    sequence(:email) { |n| "faculty#{n}@witcc.edu" }
    sequence(:first_name) { |n| "FirstName#{n}" }
    sequence(:last_name) { |n| "LastName#{n}" }
  end
end
