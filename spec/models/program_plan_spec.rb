# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe ProgramPlan do
  subject { create(:program_plan) }

  it { is_expected.to belong_to(:requirement_set) }
  it { is_expected.to have_many(:items).class_name("ProgramPlanItem").dependent(:delete_all) }
  it { is_expected.to have_many(:elective_groups).dependent(:delete_all) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:years) }
  it { is_expected.to validate_numericality_of(:years).only_integer.is_in(1..6) }
  it { is_expected.to validate_uniqueness_of(:position).scoped_to(:requirement_set_id) }

  it "lists its rows in plan order" do
    later = create(:program_plan_item, program_plan: subject, position: 2)
    earlier = create(:program_plan_item, program_plan: subject, position: 1)

    expect(subject.items).to eq([ earlier, later ])
  end
end
