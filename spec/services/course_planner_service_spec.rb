# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePlannerService do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe "#generate_plan" do
    let(:term) { create(:term, :future, uid: 202630, year: 2026, season: :fall, start_date: 6.months.from_now.to_date, end_date: 10.months.from_now.to_date) }
    let(:degree_program) { create(:degree_program) }

    before do
      create(:user_degree_program, user: user, degree_program: degree_program)
    end

    context "with unfulfilled requirements and matching courses" do
      let!(:requirement) do
        create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 2000)
      end
      let!(:course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, credit_hours: 3)
      end

      it "suggests courses that fulfill requirements" do
        result = service.generate_plan(terms: [term])

        expect(result[term]).to include(course)
      end
    end

    context "when all requirements are already completed" do
      let!(:requirement) do
        create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 1000)
      end

      before do
        create(:requirement_completion, user: user, degree_requirement: requirement, subject: "COMP", course_number: 1000)
      end

      it "returns empty suggestions" do
        result = service.generate_plan(terms: [term])

        expect(result[term]).to be_empty
      end
    end

    context "with credit hour limits" do
      before do
        # Create 7 requirements, each needing a 3-credit course = 21 credits
        7.times do |i|
          req = create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 1000 + i)
          create(:course, term: term, subject: "COMP", course_number: 1000 + i, credit_hours: 3, crn: 20000 + i)
        end
      end

      it "does not exceed 18 credit hours per term" do
        result = service.generate_plan(terms: [term])

        total = result[term].sum(&:credit_hours)
        expect(total).to be <= 18
      end
    end

    context "with multiple terms" do
      let(:term2) { create(:term, :future, uid: 202710, year: 2027, season: :spring, start_date: 12.months.from_now.to_date, end_date: 16.months.from_now.to_date) }
      let!(:req1) { create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 1000) }
      let!(:req2) { create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 2000) }
      let!(:course1) { create(:course, term: term, subject: "COMP", course_number: 1000, credit_hours: 3, crn: 30001) }
      let!(:course2) { create(:course, term: term2, subject: "COMP", course_number: 2000, credit_hours: 3, crn: 30002) }

      it "distributes courses across terms" do
        result = service.generate_plan(terms: [term, term2])

        expect(result[term]).to include(course1)
        expect(result[term2]).to include(course2)
      end
    end

    context "with no degree program" do
      before { UserDegreeProgram.where(user: user).destroy_all }

      it "returns empty suggestions" do
        result = service.generate_plan(terms: [term])

        expect(result[term]).to be_empty
      end
    end

    context "with schedule conflicts" do
      let(:room) { create(:room) }
      let!(:requirement1) { create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 1000) }
      let!(:requirement2) { create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "MATH", course_number: 2000) }
      let!(:course1) { create(:course, term: term, subject: "COMP", course_number: 1000, credit_hours: 3, crn: 40001) }
      let!(:course2) { create(:course, term: term, subject: "MATH", course_number: 2000, credit_hours: 3, crn: 40002) }

      before do
        create(:meeting_time, course: course1, room: room, day_of_week: :monday, begin_time: 1000, end_time: 1150)
        create(:meeting_time, course: course2, room: room, day_of_week: :monday, begin_time: 1100, end_time: 1250)
      end

      it "avoids scheduling conflicting courses" do
        result = service.generate_plan(terms: [term])

        # Should only pick one of the two conflicting courses
        expect(result[term].size).to eq(1)
      end
    end
  end

  describe "#validate_plan" do
    let(:term) { create(:term, :current) }

    context "with a valid plan" do
      let(:course) { create(:course, term: term, credit_hours: 3) }

      before do
        create(:course_plan, user: user, term: term, course: course,
               planned_subject: course.subject, planned_course_number: course.course_number)
      end

      it "returns valid with no issues" do
        result = service.validate_plan(term: term)

        expect(result[:valid]).to be true
        expect(result[:issues]).to be_empty
      end

      it "includes summary with credit count" do
        result = service.validate_plan(term: term)

        expect(result[:summary][:total_credits]).to eq(3)
        expect(result[:summary][:course_count]).to eq(1)
      end
    end

    context "with excessive credits" do
      before do
        7.times do |i|
          course = create(:course, term: term, credit_hours: 3, crn: 50000 + i,
                         subject: "SUBJ#{i}", course_number: 1000 + i)
          create(:course_plan, user: user, term: term, course: course,
                 planned_subject: course.subject, planned_course_number: course.course_number)
        end
      end

      it "reports credit hour issue" do
        result = service.validate_plan(term: term)

        expect(result[:valid]).to be false
        expect(result[:issues]).to include(match(/exceed maximum/))
      end
    end

    context "with schedule conflicts" do
      let(:room) { create(:room) }
      let(:course1) { create(:course, term: term, credit_hours: 3, crn: 60001, subject: "COMP", course_number: 1000) }
      let(:course2) { create(:course, term: term, credit_hours: 3, crn: 60002, subject: "MATH", course_number: 2000) }

      before do
        create(:meeting_time, course: course1, room: room, day_of_week: :monday, begin_time: 1000, end_time: 1150)
        create(:meeting_time, course: course2, room: room, day_of_week: :monday, begin_time: 1100, end_time: 1250)
        create(:course_plan, user: user, term: term, course: course1,
               planned_subject: course1.subject, planned_course_number: course1.course_number)
        create(:course_plan, user: user, term: term, course: course2,
               planned_subject: course2.subject, planned_course_number: course2.course_number)
      end

      it "detects schedule conflicts" do
        result = service.validate_plan(term: term)

        expect(result[:valid]).to be false
        expect(result[:issues]).to include(match(/Schedule conflict/))
      end
    end

    context "with unmet prerequisites" do
      let(:course) { create(:course, term: term, credit_hours: 3) }

      before do
        create(:course_prerequisite, course: course, prerequisite_rule: "COMP1000", prerequisite_type: "prerequisite")
        create(:course_plan, user: user, term: term, course: course,
               planned_subject: course.subject, planned_course_number: course.course_number)
      end

      it "reports prerequisite issues" do
        result = service.validate_plan(term: term)

        expect(result[:valid]).to be false
        expect(result[:issues]).to include(match(/Prerequisites not met/))
      end
    end

    context "with no plans" do
      it "returns valid with empty plan" do
        result = service.validate_plan(term: term)

        expect(result[:valid]).to be true
        expect(result[:issues]).to be_empty
        expect(result[:summary][:course_count]).to eq(0)
      end
    end

    context "with plans not linked to courses" do
      before do
        create(:course_plan, user: user, term: term, course: nil,
               planned_subject: "COMP", planned_course_number: 1000)
      end

      it "warns about unlinked plans" do
        result = service.validate_plan(term: term)

        expect(result[:warnings]).to include(match(/linked to actual course sections/))
      end
    end
  end
end
