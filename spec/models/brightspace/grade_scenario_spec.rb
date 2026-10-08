# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_grade_scenarios
#
#  id                 :bigint           not null, primary key
#  category_overrides :jsonb
#  name               :string           not null
#  scores             :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_brightspace_grade_scenarios_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_scenarios_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Brightspace::GradeScenario, type: :model do
  subject { create(:brightspace_grade_scenario) }

  let(:offering) { create(:brightspace_course_offering) }
  let(:item) { create(:brightspace_grade_item, course_offering: offering) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(100) }

  # The score checks read the grade items of the class, which no matcher does.
  describe "scores" do
    it "accepts points for grade items of the class" do
      scenario = build(:brightspace_grade_scenario, course_offering: offering, scores: [ { "item_id" => item.public_id, "points" => 9.5 } ])

      expect(scenario).to be_valid
    end

    it "rejects an item of another class" do
      other = create(:brightspace_grade_item)
      scenario = build(:brightspace_grade_scenario, course_offering: offering, scores: [ { "item_id" => other.public_id, "points" => 1 } ])

      expect(scenario).not_to be_valid
      expect(scenario.errors[:scores]).to include("item 0 item_id is not a grade item of this class")
    end

    it "rejects negative points, extra keys, and repeats" do
      scores = [ { "item_id" => item.public_id, "points" => -1 }, { "item_id" => item.public_id, "points" => 1, "x" => 1 },
                 { "item_id" => item.public_id, "points" => 2 } ]
      scenario = build(:brightspace_grade_scenario, course_offering: offering, scores: scores)

      expect(scenario).not_to be_valid
      expect(scenario.errors[:scores]).to include("item 0 points must be a number of 0 or more",
                                                  "item 1 must be an object with item_id and points",
                                                  "lists one item_id more than once")
    end
  end

  it "checks category overrides with the grading-rule format" do
    scenario = build(:brightspace_grade_scenario, category_overrides: [ { "weight" => 10 } ])

    expect(scenario).not_to be_valid
    expect(scenario.errors[:category_overrides]).to include("item 0 needs a name or a category_id")
  end

  it "limits the scenarios of a class" do
    stub_const("#{described_class}::MAX_PER_CLASS", 1)
    create(:brightspace_grade_scenario, course_offering: offering)

    expect(build(:brightspace_grade_scenario, course_offering: offering)).not_to be_valid
  end
end
