# frozen_string_literal: true

# == Schema Information
#
# Table name: user_degree_programs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  catalog_year          :integer          not null
#  completion_date       :date
#  declared_at           :datetime
#  primary               :boolean          default(FALSE), not null
#  program_type          :string           not null
#  status                :string           default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  degree_program_id     :bigint           not null
#  leopardweb_program_id :string
#  user_id               :bigint           not null
#
# Indexes
#
#  index_user_degree_programs_on_degree_program_id              (degree_program_id)
#  index_user_degree_programs_on_status                         (status)
#  index_user_degree_programs_on_user_id                        (user_id)
#  index_user_degree_programs_on_user_id_and_degree_program_id  (user_id,degree_program_id) UNIQUE
#  index_user_degree_programs_on_user_id_and_primary            (user_id,primary) UNIQUE WHERE ("primary" = true)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :user_degree_program do
    user
    degree_program
    program_type { "major" }
    catalog_year { 2026 }
    declared_at { 1.year.ago }
    status { "active" }
    primary { false }
    leopardweb_program_id { nil }
    completion_date { nil }

    trait :primary do
      primary { true }
    end

    trait :minor do
      program_type { "minor" }
      primary { false }
    end

    trait :completed do
      status { "completed" }
      completion_date { 1.month.ago }
    end

    trait :dropped do
      status { "dropped" }
    end
  end
end
