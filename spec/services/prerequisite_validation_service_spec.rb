# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrerequisiteValidationService, type: :service do
  subject(:result) { described_class.call(user: user, course: course) }

  let(:user) { create(:user) }
  let(:term) { create(:term) }
  let(:course) { create(:course, term: term, subject: "COMP", course_number: 2000) }

  let(:degree_requirement) { create(:degree_requirement) }


  context "when a course has no prerequisites" do
    it "returns eligible: true with empty requirements" do
      expect(result[:eligible]).to be true
      expect(result[:requirements]).to be_empty
    end
  end

  context "when a user has not completed any courses" do
    before do
      create(:course_prerequisite, course: course, prerequisite_type: "prerequisite", prerequisite_rule: "COMP 1000")
    end

    it "returns eligible: false" do
      expect(result[:eligible]).to be false
    end

    it "returns the unmet requirement" do
      req = result[:requirements].first
      expect(req[:met]).to be false
      expect(req[:type]).to eq("prerequisite")
      expect(req[:rule]).to eq("COMP 1000")
    end
  end

  context "when a user has completed the required prerequisite" do
    before do
      create(:course_prerequisite, course: course, prerequisite_type: "prerequisite", prerequisite_rule: "COMP 1000")
      create(:requirement_completion,
             user: user,
             degree_requirement: degree_requirement,
             subject: "COMP",
             course_number: 1000,
             in_progress: false)
    end

    it "returns eligible: true" do
      expect(result[:eligible]).to be true
    end

    it "marks the requirement as met" do
      req = result[:requirements].first
      expect(req[:met]).to be true
    end
  end

  context "with AND logic (must complete all)" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "COMP 1000 and MATH 2300")
    end

    context "when user has completed only one of the two" do
      before do
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "COMP",
               course_number: 1000,
               in_progress: false)
      end

      it "returns eligible: false" do
        expect(result[:eligible]).to be false
      end
    end

    context "when user has completed both" do
      before do
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "COMP",
               course_number: 1000,
               in_progress: false)
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "MATH",
               course_number: 2300,
               in_progress: false)
      end

      it "returns eligible: true" do
        expect(result[:eligible]).to be true
      end
    end
  end

  context "with OR logic (completing one is enough)" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "COMP 1000 or COMP 1050")
    end

    context "when user has completed the first option" do
      before do
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "COMP",
               course_number: 1000,
               in_progress: false)
      end

      it "returns eligible: true" do
        expect(result[:eligible]).to be true
      end
    end

    context "when user has completed neither option" do
      it "returns eligible: false" do
        expect(result[:eligible]).to be false
      end
    end
  end

  context "with a corequisite" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "corequisite",
             prerequisite_rule: "MATH 2300")
    end

    context "when user has the course in progress (not yet completed)" do
      before do
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "MATH",
               course_number: 2300,
               in_progress: true)
      end

      it "returns eligible: true because in-progress counts for corequisites" do
        expect(result[:eligible]).to be true
      end
    end

    context "when user has neither completed nor is taking the corequisite" do
      it "returns eligible: false" do
        expect(result[:eligible]).to be false
      end
    end
  end

  context "when the prerequisite is a special requirement (permission of instructor)" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "Permission of instructor")
    end

    it "returns eligible: false (cannot auto-validate)" do
      expect(result[:eligible]).to be false
    end

    it "marks the requirement as unmet" do
      req = result[:requirements].first
      expect(req[:met]).to be false
    end
  end

  context "with multiple prerequisites (all must be met)" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "COMP 1000")
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "MATH 2300")
    end

    context "when user has completed only one" do
      before do
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "COMP",
               course_number: 1000,
               in_progress: false)
      end

      it "returns eligible: false" do
        expect(result[:eligible]).to be false
      end

      it "returns two requirements, one met and one not" do
        reqs = result[:requirements]
        expect(reqs.count { |r| r[:met] }).to eq(1)
        expect(reqs.count { |r| !r[:met] }).to eq(1)
      end
    end
  end

  context "waivable flag is included in the result" do
    before do
      create(:course_prerequisite,
             course: course,
             prerequisite_type: "prerequisite",
             prerequisite_rule: "COMP 1000",
             waivable: true)
    end

    it "includes waivable: true in the requirement result" do
      req = result[:requirements].first
      expect(req[:waivable]).to be true
    end
  end
end
