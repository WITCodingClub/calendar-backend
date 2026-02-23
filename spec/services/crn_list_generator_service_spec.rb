# frozen_string_literal: true

require "rails_helper"

RSpec.describe CrnListGeneratorService do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  describe "#call" do
    context "with no planned courses" do
      it "returns empty courses list" do
        result = described_class.call(user: user, term: term)
        expect(result[:courses]).to be_empty
        expect(result[:summary][:total_planned]).to eq(0)
      end

      it "returns term info" do
        result = described_class.call(user: user, term: term)
        expect(result[:term][:uid]).to eq(term.uid)
        expect(result[:term][:name]).to eq(term.name)
      end

      it "returns zero credits and empty crn_list" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:total_credits]).to eq(0)
        expect(result[:summary][:crn_list]).to eq("")
        expect(result[:summary][:has_conflicts]).to be false
      end
    end

    context "with planned courses" do
      let(:course) { create(:course, term: term, crn: 12345, credit_hours: 3) }

      before do
        create(:course_plan, user: user, term: term, course: course,
               planned_subject: course.subject,
               planned_course_number: course.course_number,
               planned_crn: course.crn)
      end

      it "includes the planned course" do
        result = described_class.call(user: user, term: term)
        expect(result[:courses].size).to eq(1)
        expect(result[:courses].first[:crn]).to eq(12345)
      end

      it "calculates total credits" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:total_credits]).to eq(3)
      end

      it "includes crn_list string" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:crn_list]).to include("12345")
      end

      it "marks entry type as planned" do
        result = described_class.call(user: user, term: term)
        expect(result[:courses].first[:type]).to eq("planned")
      end

      it "has no conflicts" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:has_conflicts]).to be false
        expect(result[:courses].first[:conflict]).to be false
      end
    end

    context "with a course plan that has no linked course record" do
      before do
        create(:course_plan, user: user, term: term, course: nil,
               planned_subject: "COMP",
               planned_course_number: 1500,
               planned_crn: 99999)
      end

      it "includes the unmatched plan entry" do
        result = described_class.call(user: user, term: term)
        expect(result[:courses].size).to eq(1)
        entry = result[:courses].first
        expect(entry[:course]).to be_nil
        expect(entry[:planned_subject]).to eq("COMP")
        expect(entry[:planned_course_number]).to eq(1500)
        expect(entry[:crn]).to eq(99999)
        expect(entry[:meeting_times]).to be_empty
      end
    end

    context "with only completed/dropped courses" do
      let(:course) { create(:course, term: term) }

      before do
        create(:course_plan, user: user, term: term, course: course,
               planned_subject: course.subject,
               planned_course_number: course.course_number,
               status: "completed")
        create(:course_plan, user: user, term: term, course: nil,
               planned_subject: "COMP",
               planned_course_number: 1000,
               status: "dropped")
      end

      it "does not include completed or dropped plans" do
        result = described_class.call(user: user, term: term)
        expect(result[:courses]).to be_empty
      end
    end

    context "with schedule conflicts" do
      let(:course1) { create(:course, term: term, crn: 11111) }
      let(:course2) { create(:course, term: term, crn: 22222) }

      before do
        # Both courses have overlapping Monday meetings
        create(:meeting_time, course: course1, day_of_week: :monday,
               begin_time: 900, end_time: 1030)
        create(:meeting_time, course: course2, day_of_week: :monday,
               begin_time: 1000, end_time: 1130)

        create(:course_plan, user: user, term: term, course: course1,
               planned_subject: course1.subject,
               planned_course_number: course1.course_number)
        create(:course_plan, user: user, term: term, course: course2,
               planned_subject: course2.subject,
               planned_course_number: course2.course_number)
      end

      it "marks conflicting courses" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:has_conflicts]).to be true
        expect(result[:courses].all? { |c| c[:conflict] }).to be true
      end
    end

    context "without schedule conflicts" do
      let(:course1) { create(:course, term: term, crn: 11111) }
      let(:course2) { create(:course, term: term, crn: 22222) }

      before do
        # Non-overlapping Monday meetings
        create(:meeting_time, course: course1, day_of_week: :monday,
               begin_time: 900, end_time: 1030)
        create(:meeting_time, course: course2, day_of_week: :monday,
               begin_time: 1100, end_time: 1230)

        create(:course_plan, user: user, term: term, course: course1,
               planned_subject: course1.subject,
               planned_course_number: course1.course_number)
        create(:course_plan, user: user, term: term, course: course2,
               planned_subject: course2.subject,
               planned_course_number: course2.course_number)
      end

      it "does not mark courses as conflicting" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:has_conflicts]).to be false
        expect(result[:courses].none? { |c| c[:conflict] }).to be true
      end
    end

    context "with courses on different days" do
      let(:course1) { create(:course, term: term, crn: 11111) }
      let(:course2) { create(:course, term: term, crn: 22222) }

      before do
        # Same time slot but different days — no conflict
        create(:meeting_time, course: course1, day_of_week: :monday,
               begin_time: 900, end_time: 1030)
        create(:meeting_time, course: course2, day_of_week: :wednesday,
               begin_time: 900, end_time: 1030)

        create(:course_plan, user: user, term: term, course: course1,
               planned_subject: course1.subject,
               planned_course_number: course1.course_number)
        create(:course_plan, user: user, term: term, course: course2,
               planned_subject: course2.subject,
               planned_course_number: course2.course_number)
      end

      it "does not flag different-day courses as conflicting" do
        result = described_class.call(user: user, term: term)
        expect(result[:summary][:has_conflicts]).to be false
      end
    end
  end
end
