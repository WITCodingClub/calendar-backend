# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseRecommendationService do
  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202430, year: 2024, season: :fall) }
  let(:degree_program) { create(:degree_program) }

  before do
    create(:user_degree_program, user: user, degree_program: degree_program, primary: true)
  end

  describe ".call" do
    it "returns the term info and recommendations array" do
      result = described_class.call(user: user, term: term)

      expect(result).to have_key(:term)
      expect(result[:term][:uid]).to eq(202430)
      expect(result[:term][:name]).to eq("Fall 2024")
      expect(result).to have_key(:recommendations)
      expect(result).to have_key(:total)
    end

    context "with available courses" do
      let!(:course) do
        create(:course, term: term, subject: "COMP", course_number: 2000,
                        title: "Data Structures", crn: 12345, credit_hours: 3)
      end

      it "includes courses from the given term" do
        result = described_class.call(user: user, term: term)

        expect(result[:total]).to eq(1)
        rec = result[:recommendations].first
        expect(rec[:course][:subject]).to eq("COMP")
        expect(rec[:course][:course_number]).to eq(2000)
        expect(rec[:course][:title]).to eq("Data Structures")
        expect(rec[:course][:crn]).to eq(12345)
        expect(rec[:course][:credits]).to eq(3)
      end

      it "marks prerequisite status as met when no prerequisites exist" do
        result = described_class.call(user: user, term: term)

        rec = result[:recommendations].first
        expect(rec[:prerequisite_status]).to eq("met")
      end
    end

    context "excluding planned courses" do
      let!(:planned_course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 12345)
      end
      let!(:unplanned_course) do
        create(:course, term: term, subject: "COMP", course_number: 3000, crn: 12346)
      end

      before do
        create(:course_plan, user: user, term: term, course: planned_course,
                             planned_subject: "COMP", planned_course_number: 2000,
                             planned_crn: 12345, status: "planned")
      end

      it "excludes courses already in the user's plan" do
        result = described_class.call(user: user, term: term)

        course_numbers = result[:recommendations].map { |r| r[:course][:course_number] }
        expect(course_numbers).not_to include(2000)
        expect(course_numbers).to include(3000)
      end
    end

    context "excluding completed courses" do
      let!(:completed_course) do
        create(:course, term: term, subject: "COMP", course_number: 1000, crn: 11111)
      end
      let!(:incomplete_course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222)
      end

      before do
        req = create(:degree_requirement, degree_program: degree_program,
                                          subject: "COMP", course_number: 1000)
        create(:requirement_completion, user: user, degree_requirement: req,
                                        subject: "COMP", course_number: 1000,
                                        met_requirement: true, in_progress: false, grade: "A")
      end

      it "excludes courses the user has already completed" do
        result = described_class.call(user: user, term: term)

        course_numbers = result[:recommendations].map { |r| r[:course][:course_number] }
        expect(course_numbers).not_to include(1000)
        expect(course_numbers).to include(2000)
      end
    end

    context "ranking by priority" do
      let!(:required_course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222)
      end
      let!(:elective_course) do
        create(:course, term: term, subject: "ARTS", course_number: 1000, crn: 33333)
      end

      before do
        create(:degree_requirement, degree_program: degree_program,
                                    subject: "COMP", course_number: 2000,
                                    area_name: "Core CS Requirements")
      end

      it "puts required courses before electives" do
        result = described_class.call(user: user, term: term)

        expect(result[:recommendations].size).to eq(2)
        expect(result[:recommendations].first[:priority]).to eq("required")
        expect(result[:recommendations].first[:fulfills_requirement]).to eq("Core CS Requirements")
        expect(result[:recommendations].last[:priority]).to eq("elective")
        expect(result[:recommendations].last[:fulfills_requirement]).to be_nil
      end
    end

    context "schedule conflict detection" do
      let!(:planned_course) do
        create(:course, term: term, subject: "COMP", course_number: 1500, crn: 11111)
      end
      let!(:conflicting_course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222)
      end
      let!(:non_conflicting_course) do
        create(:course, term: term, subject: "COMP", course_number: 3000, crn: 33333)
      end

      before do
        # planned course on Monday 9:00-10:00
        create(:meeting_time, course: planned_course, day_of_week: :monday,
                              begin_time: 900, end_time: 1000)
        # conflicting course also Monday 9:30-10:30
        create(:meeting_time, course: conflicting_course, day_of_week: :monday,
                              begin_time: 930, end_time: 1030)
        # non-conflicting on Tuesday
        create(:meeting_time, course: non_conflicting_course, day_of_week: :tuesday,
                              begin_time: 900, end_time: 1000)

        create(:course_plan, user: user, term: term, course: planned_course,
                             planned_subject: "COMP", planned_course_number: 1500,
                             planned_crn: 11111, status: "planned")
      end

      it "detects schedule conflicts with planned courses" do
        result = described_class.call(user: user, term: term)

        recs_by_crn = result[:recommendations].index_by { |r| r[:course][:crn] }
        expect(recs_by_crn[22222][:schedule_conflicts]).to be true
        expect(recs_by_crn[33333][:schedule_conflicts]).to be false
      end

      it "ranks non-conflicting courses before conflicting ones" do
        result = described_class.call(user: user, term: term)

        crns = result[:recommendations].map { |r| r[:course][:crn] }
        non_conflict_idx = crns.index(33333)
        conflict_idx = crns.index(22222)
        expect(non_conflict_idx).to be < conflict_idx
      end
    end

    context "with RMP ratings" do
      let(:faculty_high) { create(:faculty, first_name: "Good", last_name: "Prof", email: "good@wit.edu") }
      let(:faculty_low) { create(:faculty, first_name: "Low", last_name: "Prof", email: "low@wit.edu") }

      let!(:high_rated_course) do
        course = create(:course, term: term, subject: "COMP", course_number: 3000, crn: 33333)
        course.faculties << faculty_high
        course
      end
      let!(:low_rated_course) do
        course = create(:course, term: term, subject: "COMP", course_number: 4000, crn: 44444)
        course.faculties << faculty_low
        course
      end

      before do
        create(:rating_distribution, faculty: faculty_high, avg_rating: 4.5, num_ratings: 20, total: 20)
        create(:rating_distribution, faculty: faculty_low, avg_rating: 2.5, num_ratings: 10, total: 10)
      end

      it "includes faculty RMP rating in course data" do
        result = described_class.call(user: user, term: term)

        recs_by_crn = result[:recommendations].index_by { |r| r[:course][:crn] }
        expect(recs_by_crn[33333][:course][:faculty][:rmp_rating]).to eq(4.5)
        expect(recs_by_crn[44444][:course][:faculty][:rmp_rating]).to eq(2.5)
      end

      it "ranks higher-rated courses first within same priority" do
        result = described_class.call(user: user, term: term)

        crns = result[:recommendations].map { |r| r[:course][:crn] }
        high_idx = crns.index(33333)
        low_idx = crns.index(44444)
        expect(high_idx).to be < low_idx
      end
    end

    context "with cancelled courses" do
      let!(:active_course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222, status: :active)
      end
      let!(:cancelled_course) do
        create(:course, term: term, subject: "COMP", course_number: 3000, crn: 33333, status: :cancelled)
      end

      it "excludes cancelled courses" do
        result = described_class.call(user: user, term: term)

        crns = result[:recommendations].map { |r| r[:course][:crn] }
        expect(crns).to include(22222)
        expect(crns).not_to include(33333)
      end
    end

    context "with no degree program" do
      before do
        UserDegreeProgram.where(user: user).destroy_all
      end

      let!(:course) do
        create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222)
      end

      it "still returns courses as electives" do
        result = described_class.call(user: user, term: term)

        expect(result[:total]).to eq(1)
        expect(result[:recommendations].first[:priority]).to eq("elective")
      end
    end

    context "with no courses in term" do
      it "returns empty recommendations" do
        result = described_class.call(user: user, term: term)

        expect(result[:recommendations]).to be_empty
        expect(result[:total]).to eq(0)
      end
    end
  end
end
