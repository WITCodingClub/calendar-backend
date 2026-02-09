# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePrerequisite do
  describe "validations" do
    it { is_expected.to validate_presence_of(:prerequisite_type) }
    it { is_expected.to validate_presence_of(:prerequisite_rule) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:course) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:prerequisite_type).with_values(prerequisite: "prerequisite", corequisite: "corequisite", recommended: "recommended") }
  end

  describe "scopes" do
    let(:course) { create(:course, term: create(:term)) }
    let!(:prerequisite) { create(:course_prerequisite, course: course, prerequisite_type: :prerequisite) }
    let!(:corequisite) { create(:course_prerequisite, :corequisite, course: course) }
    let!(:recommended) { create(:course_prerequisite, :recommended, course: course) }
    let!(:waivable) { create(:course_prerequisite, :waivable, course: course) }

    describe ".by_type" do
      it "returns prerequisites of the specified type" do
        expect(described_class.by_type(:prerequisite)).to include(prerequisite)
        expect(described_class.by_type(:prerequisite)).not_to include(corequisite)
      end
    end

    describe ".required" do
      it "returns only required prerequisites and corequisites" do
        expect(described_class.required).to include(prerequisite, corequisite)
        expect(described_class.required).not_to include(recommended)
      end
    end

    describe ".waivable_only" do
      it "returns only waivable prerequisites" do
        expect(described_class.waivable_only).to include(waivable)
        expect(described_class.waivable_only).not_to include(prerequisite)
      end
    end
  end

  describe "#extract_course_codes" do
    it "extracts course codes from prerequisite rule" do
      prereq = create(:course_prerequisite, prerequisite_rule: "COMP1000 and MATH2300")
      expect(prereq.extract_course_codes).to contain_exactly("COMP1000", "MATH2300")
    end

    it "handles complex logic with parentheses" do
      prereq = create(:course_prerequisite, :complex_logic, prerequisite_rule: "(COMP1000 and MATH2300) or (COMP1050 and MATH1777)")
      expect(prereq.extract_course_codes).to contain_exactly("COMP1000", "MATH2300", "COMP1050", "MATH1777")
    end

    it "returns empty array when no course codes found" do
      prereq = create(:course_prerequisite, prerequisite_rule: "Instructor permission required")
      expect(prereq.extract_course_codes).to be_empty
    end
  end
end
