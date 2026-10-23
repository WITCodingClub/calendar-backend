# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_programs
#
#  id                :bigint           not null, primary key
#  kind              :string           not null
#  level             :string           not null
#  name              :string           not null
#  slug              :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  parent_program_id :bigint
#
# Indexes
#
#  index_degree_programs_on_parent_program_id  (parent_program_id)
#  index_degree_programs_on_slug               (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (parent_program_id => degree_programs.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :degree_program do
    sequence(:slug) { |n| "program-#{n}-bs" }
    name { "#{Faker::Educator.subject}, B.S." }
    kind { "bachelor" }
    level { "undergraduate" }

    trait :master do
      sequence(:slug) { |n| "program-#{n}-ms" }
      kind { "master" }
      level { "graduate" }
    end

    trait :minor do
      sequence(:slug) { |n| "program-#{n}-minor" }
      kind { "minor" }
    end

    trait :concentration do
      sequence(:slug) { |n| "program-#{n}-concentration" }
      kind { "concentration" }
      parent_program factory: :degree_program
    end
  end
end
