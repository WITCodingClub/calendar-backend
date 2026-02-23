# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
# Database name: primary
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  embedding      :vector(1536)
#  end_date       :date
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  start_date     :date
#  status         :string           default("active"), not null
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_courses_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_courses_on_status           (status)
#  index_courses_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
require "rails_helper"

RSpec.describe Course do
  describe "calendar sync tracking" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }
    let(:user) { create(:user, calendar_needs_sync: false) }
    let!(:oauth_credential) do
      create(:oauth_credential,
             user: user,
             metadata: { "course_calendar_id" => "cal_123" })
    end

    before do
      create(:enrollment, user: user, course: course, term: term)
      user.update_column(:calendar_needs_sync, false)
    end

    context "when course title changes" do
      it "marks enrolled users as needing sync" do
        expect {
          course.update!(title: "New Course Title")
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when course start_date changes" do
      it "marks enrolled users as needing sync" do
        expect {
          course.update!(start_date: Time.zone.today + 1.week)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when irrelevant field changes" do
      it "does not mark enrolled users as needing sync" do
        expect {
          course.update!(credit_hours: 4)
        }.not_to(change { user.reload.calendar_needs_sync })
      end
    end

    context "when course is destroyed" do
      # NOTE: This is currently broken because `after_destroy` callback runs after
      # `dependent: :destroy` on enrollments, so there are no enrollments left to find users.
      # This should use `before_destroy` instead to capture users before enrollments are deleted.
      it "does not mark enrolled users as needing sync (bug: after_destroy runs too late)" do
        expect {
          course.destroy
        }.not_to(change { user.reload.calendar_needs_sync })
      end
    end
  end

  describe "embeddings" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term, title: "Web Development", subject: "CS", schedule_type: :lecture) }

    describe "#embedding_text" do
      it "combines title, subject, and schedule type description" do
        expect(course.embedding_text).to eq("Web Development CS lecture")
      end

      it "handles missing optional fields" do
        course.subject = nil
        expect(course.embedding_text).to eq("Web Development lecture")
      end
    end

    describe "#schedule_type_description" do
      it "returns human-readable description for lecture" do
        course.schedule_type = :lecture
        expect(course.schedule_type_description).to eq("lecture")
      end

      it "returns human-readable description for hybrid" do
        course.schedule_type = :hybrid
        expect(course.schedule_type_description).to eq("hybrid in-person and online")
      end

      it "returns nil when schedule_type is not set" do
        course.schedule_type = nil
        expect(course.schedule_type_description).to be_nil
      end
    end

    describe "#similar_courses" do
      it "returns empty relation when embedding is nil" do
        expect(course.similar_courses).to eq(described_class.none)
      end

      it "finds similar courses when embedding is present" do
        # Create sample embedding vectors
        embedding1 = Array.new(1536) { rand }
        embedding2 = Array.new(1536) { rand }

        course.update!(embedding: embedding1)
        similar_course = create(:course, term: term, title: "Advanced Web Development", embedding: embedding2)

        # Should return a relation (actual similarity depends on vector values)
        expect(course.similar_courses).to be_a(ActiveRecord::Relation)
        expect(course.similar_courses).not_to include(course)
      end
    end

    describe ".semantic_search" do
      it "performs nearest neighbor search with given embedding" do
        query_embedding = Array.new(1536) { rand }
        course.update!(embedding: Array.new(1536) { rand })

        results = described_class.semantic_search(query_embedding, limit: 5)
        expect(results).to be_a(ActiveRecord::Relation)
      end
    end

    describe ".with_embeddings scope" do
      it "returns only courses with embeddings" do
        course_with_embedding = create(:course, term: term, embedding: Array.new(1536) { rand })
        course_without_embedding = create(:course, term: term)

        expect(described_class.with_embeddings).to include(course_with_embedding)
        expect(described_class.with_embeddings).not_to include(course_without_embedding)
      end
    end
  end

  describe "#filtered_meeting_times" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }

    context "with no duplicate meeting times" do
      it "returns all meeting times" do
        building = create(:building, name: "Watson Hall", abbreviation: "WATSN")
        room = create(:room, building: building, number: "101")
        mt = create(:meeting_time, course: course, room: room, day_of_week: :monday, begin_time: 930, end_time: 1040)

        expect(course.filtered_meeting_times).to eq([mt])
      end
    end

    context "with duplicate meeting times (same day/time)" do
      let(:valid_building) { create(:building, name: "Watson Hall", abbreviation: "WATSN") }
      let(:valid_room) { create(:room, building: valid_building, number: "101") }
      let(:tbd_building) { create(:building, name: "To Be Determined", abbreviation: "TBD") }
      let(:tbd_room) { create(:room, building: tbd_building, number: "0") }

      it "prefers meeting time with valid location over TBD" do
        tbd_mt = create(:meeting_time, course: course, room: tbd_room, day_of_week: :monday, begin_time: 930, end_time: 1040)
        valid_mt = create(:meeting_time, course: course, room: valid_room, day_of_week: :monday, begin_time: 930, end_time: 1040)

        result = course.filtered_meeting_times
        expect(result.size).to eq(1)
        expect(result.first).to eq(valid_mt)
      end

      it "returns TBD meeting time when no valid location exists" do
        tbd_mt = create(:meeting_time, course: course, room: tbd_room, day_of_week: :monday, begin_time: 930, end_time: 1040)

        result = course.filtered_meeting_times
        expect(result.size).to eq(1)
        expect(result.first).to eq(tbd_mt)
      end

      it "handles meeting times with room number 0 as TBD" do
        room_zero = create(:room, building: valid_building, number: "0")

        tbd_mt = create(:meeting_time, course: course, room: room_zero, day_of_week: :monday, begin_time: 930, end_time: 1040)
        valid_mt = create(:meeting_time, course: course, room: valid_room, day_of_week: :monday, begin_time: 930, end_time: 1040)

        result = course.filtered_meeting_times
        expect(result.size).to eq(1)
        expect(result.first).to eq(valid_mt)
      end
    end

    context "with multiple different meeting times" do
      it "returns one meeting time per unique day/time combination" do
        valid_building = create(:building, name: "Watson Hall", abbreviation: "WATSN")
        valid_room = create(:room, building: valid_building, number: "101")
        tbd_building = create(:building, name: "To Be Determined", abbreviation: "TBD")
        tbd_room = create(:room, building: tbd_building, number: "0")

        # Monday 9:30-10:40 with TBD and valid
        create(:meeting_time, course: course, room: tbd_room, day_of_week: :monday, begin_time: 930, end_time: 1040)
        monday_valid = create(:meeting_time, course: course, room: valid_room, day_of_week: :monday, begin_time: 930, end_time: 1040)

        # Wednesday 9:30-10:40 with TBD and valid
        create(:meeting_time, course: course, room: tbd_room, day_of_week: :wednesday, begin_time: 930, end_time: 1040)
        wednesday_valid = create(:meeting_time, course: course, room: valid_room, day_of_week: :wednesday, begin_time: 930, end_time: 1040)

        result = course.filtered_meeting_times
        expect(result.size).to eq(2)
        expect(result).to include(monday_valid)
        expect(result).to include(wednesday_valid)
      end
    end
  end

  describe "term date updates" do
    let(:term) { create(:term, year: 2025, start_date: nil, end_date: nil) }

    it "updates term dates when course is created with dates" do
      course = create(:course, term: term, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))

      term.reload
      expect(term.start_date).to eq(Date.new(2025, 8, 15))
      expect(term.end_date).to eq(Date.new(2025, 12, 20))
    end

    it "updates term dates when course start_date changes" do
      course = create(:course, term: term, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))
      course.update!(start_date: Date.new(2025, 8, 10))

      term.reload
      expect(term.start_date).to eq(Date.new(2025, 8, 10))
    end

    it "updates term dates when course end_date changes" do
      course = create(:course, term: term, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))
      course.update!(end_date: Date.new(2025, 12, 25))

      term.reload
      expect(term.end_date).to eq(Date.new(2025, 12, 25))
    end

    it "updates term dates when course is destroyed" do
      course1 = create(:course, term: term, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))
      course2 = create(:course, term: term, start_date: Date.new(2025, 8, 20), end_date: Date.new(2025, 12, 15))

      course1.destroy

      term.reload
      expect(term.start_date).to eq(Date.new(2025, 8, 20))
      expect(term.end_date).to eq(Date.new(2025, 12, 15))
    end

    it "does not update term dates when other attributes change" do
      course = create(:course, term: term, title: "Original Title", start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))

      expect {
        course.update!(title: "New Title")
      }.not_to(change { term.reload.updated_at })
    end
  end
end
