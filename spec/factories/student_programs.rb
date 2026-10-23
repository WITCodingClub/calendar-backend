# frozen_string_literal: true

# == Schema Information
#
# Table name: student_programs
#
#  id               :bigint           not null, primary key
#  catalog_term_uid :integer
#  code             :string
#  college          :string
#  concentration    :string
#  degree           :string
#  department       :string
#  ended_at         :datetime
#  name             :string           not null
#  role             :string           not null
#  source           :string           not null
#  status           :string           default("active"), not null
#  study_path       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_student_programs_on_user_id_and_status  (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :student_program do
    user
    role { "major" }
    sequence(:code) { |n| "BPRG#{n}" }
    name { Faker::Educator.subject }
    degree { "Bachelor of Science" }
    catalog_term_uid { 202610 }
    source { "leopardweb" }

    trait :minor do
      role { "minor" }
      code { nil }
      degree { nil }
    end

    trait :ended do
      status { "ended" }
      ended_at { 1.day.ago }
    end
  end
end
