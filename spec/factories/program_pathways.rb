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
    sequence(:slug) { |n| "pathway-#{n}-4-plus-1" }
    name { "#{Faker::Educator.subject} 4+1" }
    kind { "four_plus_one" }
    max_shared_courses { 2 }
  end
end
