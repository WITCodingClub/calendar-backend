# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: elective_groups
#
#  id                 :bigint           not null, primary key
#  heading            :text
#  min_courses        :integer
#  min_credits        :integer
#  name               :string           not null
#  notes              :text
#  position           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  program_plan_id    :bigint
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  index_elective_groups_on_program_plan_id     (program_plan_id)
#  index_elective_groups_on_requirement_set_id  (requirement_set_id)
#
# Foreign Keys
#
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#  fk_rails_...  (requirement_set_id => requirement_sets.id) ON DELETE => cascade
#
RSpec.describe ElectiveGroup do
  subject { create(:elective_group) }

  it { is_expected.to belong_to(:requirement_set) }
  it { is_expected.to belong_to(:program_plan).optional }
  it { is_expected.to have_many(:courses).class_name("ElectiveGroupCourse").dependent(:delete_all) }
  it { is_expected.to have_many(:program_plan_items).dependent(:nullify) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:min_courses).only_integer.is_greater_than(0).allow_nil }
  it { is_expected.to validate_numericality_of(:min_credits).only_integer.is_greater_than(0).allow_nil }

  # A cross-record check, so no matcher covers it.
  it "takes a plan only from its own requirement set" do
    expect(build(:elective_group, :for_plan)).to be_valid

    group = build(:elective_group, program_plan: create(:program_plan))
    expect(group).not_to be_valid
    expect(group.errors[:program_plan]).to be_present
  end

  it "lists its courses in page order" do
    second = create(:elective_group_course, elective_group: subject, position: 2)
    first = create(:elective_group_course, elective_group: subject, position: 1)

    expect(subject.courses).to eq([ first, second ])
  end
end
