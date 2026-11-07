# frozen_string_literal: true

# == Schema Information
#
# Table name: program_pathways
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  kind               :string           not null
#  max_shared_courses :integer
#  max_shared_credits :integer
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_program_pathways_on_slug  (slug) UNIQUE
#
FactoryBot.define do
  factory :program_pathway do
    sequence(:slug) { |n| "pathway-#{n}" }
    name { "#{Faker::Educator.subject} B.S. and M.S." }
    kind { "combined" }

    trait :double_leopard do
      sequence(:slug) { |n| "double-leopard-pathway-#{n}" }
      kind { "double_leopard" }
      max_shared_courses { 2 }
    end
  end
end
