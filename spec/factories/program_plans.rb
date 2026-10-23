# frozen_string_literal: true

# == Schema Information
#
# Table name: program_plans
#
#  id                 :bigint           not null, primary key
#  accelerated        :boolean          default(FALSE), not null
#  name               :string           not null
#  position           :integer          default(0), not null
#  total_credits      :integer
#  years              :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  index_program_plans_on_requirement_set_id_and_position  (requirement_set_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (requirement_set_id => requirement_sets.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :program_plan do
    requirement_set
    name { "Four Year Program" }
    years { 4 }
    sequence(:position)

    trait :accelerated do
      name { "Three Year Program" }
      years { 3 }
      accelerated { true }
    end
  end
end
