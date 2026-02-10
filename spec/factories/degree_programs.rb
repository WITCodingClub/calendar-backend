# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_programs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  catalog_year          :integer          not null
#  college               :string
#  credit_hours_required :decimal(5, 2)
#  degree_type           :string           not null
#  department            :string
#  leopardweb_code       :string           not null
#  level                 :string           not null
#  minimum_gpa           :decimal(3, 2)
#  program_code          :string           not null
#  program_name          :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_degree_programs_on_active                         (active)
#  index_degree_programs_on_catalog_year_and_program_code  (catalog_year,program_code)
#  index_degree_programs_on_leopardweb_code                (leopardweb_code) UNIQUE
#  index_degree_programs_on_program_code                   (program_code) UNIQUE
#
FactoryBot.define do
  factory :degree_program do
    sequence(:program_code) { |n| "PROG#{n}" }
    sequence(:leopardweb_code) { |n| "P2026#{n.to_s.rjust(2, '0')}" }
    sequence(:program_name) { |n| "Test Program #{n}" }
    degree_type { "Bachelor of Science" }
    level { "Undergraduate" }
    college { "College of Engineering and Sciences" }
    department { "Computer Science" }
    catalog_year { 2026 }
    credit_hours_required { 120.0 }
    minimum_gpa { 2.0 }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :graduate do
      level { "Graduate" }
      degree_type { "Master of Science" }
      credit_hours_required { 30.0 }
      minimum_gpa { 3.0 }
    end

    trait :with_requirements do
      after(:create) do |program|
        create_list(:degree_requirement, 3, degree_program: program)
      end
    end
  end
end
