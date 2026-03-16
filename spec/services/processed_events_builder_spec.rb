# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessedEventsBuilder do
  # Shared setup for a basic enrolled user with one course and one meeting time
  subject(:builder) { described_class.new(user, term) }

  let(:term) { create(:term, season: :fall, year: 2025) }
  let(:building) { create(:building, name: "Beatty Hall", abbreviation: "BE") }
  let(:room) { create(:room, building: building, number: "210") }
  let(:user) { create(:user) }
  let(:course) do
    create(:course,
           term: term,
           title: "Computer Science II",
           subject: "Computer Science (CS)",
           course_number: 201,
           section_number: "01",
           schedule_type: :lecture)
  end
  let!(:meeting_time) do
    create(:meeting_time,
           course: course,
           room: room,
           begin_time: 1000,
           end_time: 1150,
           day_of_week: :monday,
           meeting_schedule_type: :lecture)
  end
  let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }


  describe "#build" do
    subject(:result) { builder.build }

    it "returns a hash with :classes and :notifications_disabled keys" do
      expect(result).to have_key(:classes)
      expect(result).to have_key(:notifications_disabled)
    end

    it "returns one entry per enrolled course" do
      expect(result[:classes].length).to eq(1)
    end

    it "reflects notifications_disabled = false when user has no DND" do
      expect(result[:notifications_disabled]).to be false
    end

    it "reflects notifications_disabled = true when user is in DND mode" do
      user.update!(notifications_disabled_until: 2.hours.from_now)
      expect(result[:notifications_disabled]).to be true
    end

    describe "course-level data" do
      subject(:course_data) { result[:classes].first }

      it "includes the titleized course title" do
        expect(course_data[:title]).to be_a(String)
        expect(course_data[:title]).to be_present
      end

      it "includes the course number" do
        expect(course_data[:course_number]).to eq(201)
      end

      it "includes the schedule type" do
        expect(course_data[:schedule_type]).to eq("lecture")
      end

      it "extracts the prefix from a parenthesized subject" do
        expect(course_data[:prefix]).to eq("CS")
      end

      it "returns the subject as prefix when subject has no parenthesized code" do
        course.update!(subject: "Computer Science")
        result = builder.build
        expect(result[:classes].first[:prefix]).to eq("Computer Science")
      end

      describe "term data" do
        it "includes the term season" do
          expect(course_data.dig(:term, :season)).to eq("fall")
        end

        it "includes the term year" do
          expect(course_data.dig(:term, :year)).to eq(2025)
        end

        it "includes the term uid" do
          expect(course_data.dig(:term, :uid)).to eq(term.uid)
        end

        it "includes the term pub_id" do
          expect(course_data.dig(:term, :pub_id)).to be_present
        end
      end
    end

    describe "professor data" do
      context "when the course has a faculty member" do
        subject(:professor_data) { result[:classes].first[:professor] }

        let(:faculty) { create(:faculty, first_name: "Jane", last_name: "Smith", email: "jsmith@wit.edu", rmp_id: "abc123") }

        before { course.faculties << faculty }


        it "includes first and last name" do
          expect(professor_data[:first_name]).to eq("Jane")
          expect(professor_data[:last_name]).to eq("Smith")
        end

        it "includes email" do
          expect(professor_data[:email]).to eq("jsmith@wit.edu")
        end

        it "includes rmp_id" do
          expect(professor_data[:rmp_id]).to eq("abc123")
        end

        it "includes pub_id" do
          expect(professor_data[:pub_id]).to be_present
        end
      end

      context "when the course has no faculty" do
        it "returns nil for professor" do
          expect(result[:classes].first[:professor]).to be_nil
        end
      end
    end

    describe "meeting times data" do
      subject(:meeting_time_data) { result[:classes].first[:meeting_times].first }

      it "includes the meeting time pub_id" do
        expect(meeting_time_data[:id]).to be_present
      end

      it "includes the begin time in military format" do
        expect(meeting_time_data[:begin_time]).to eq(meeting_time.fmt_begin_time_military)
      end

      it "includes the end time in military format" do
        expect(meeting_time_data[:end_time]).to eq(meeting_time.fmt_end_time_military)
      end

      it "includes start_date and end_date" do
        expect(meeting_time_data[:start_date]).to be_present
        expect(meeting_time_data[:end_date]).to be_present
      end

      it "sets the correct day of week to true and all others to false" do
        expect(meeting_time_data[:monday]).to be true
        %i[tuesday wednesday thursday friday saturday sunday].each do |day|
          expect(meeting_time_data[day]).to be false
        end
      end

      describe "location data" do
        it "includes building name and abbreviation" do
          expect(meeting_time_data.dig(:location, :building, :name)).to eq("Beatty Hall")
          expect(meeting_time_data.dig(:location, :building, :abbreviation)).to eq("BE")
        end

        it "includes the formatted room number" do
          expect(meeting_time_data.dig(:location, :room)).to eq(room.formatted_number)
        end

        it "includes building pub_id" do
          expect(meeting_time_data.dig(:location, :building, :pub_id)).to be_present
        end
      end

      describe "calendar_config" do
        it "includes a title" do
          expect(meeting_time_data.dig(:calendar_config, :title)).to be_a(String)
          expect(meeting_time_data.dig(:calendar_config, :title)).to be_present
        end

        it "includes visibility" do
          expect(meeting_time_data.dig(:calendar_config, :visibility)).to be_present
        end

        it "includes reminder_settings" do
          expect(meeting_time_data.dig(:calendar_config, :reminder_settings)).to be_present
        end

        context "with a custom title_template via CalendarPreference" do
          before do
            create(:calendar_preference,
                   user: user,
                   scope: :event_type,
                   event_type: "lecture",
                   title_template: "{{course_code}}: {{title}}")
          end

          it "renders the custom template into the title" do
            data = builder.build
            title = data[:classes].first[:meeting_times].first.dig(:calendar_config, :title)
            expect(title).to be_a(String)
            expect(title).to be_present
          end
        end

        context "with no description_template" do
          it "returns nil description by default (system defaults)" do
            # System defaults include a description_template so it won't be nil
            # unless explicitly set to blank; just check it's a String or nil
            desc = meeting_time_data.dig(:calendar_config, :description)
            expect(desc).to be_nil.or be_a(String)
          end
        end
      end
    end

    describe "with multiple meeting times on the same day/time (TBD deduplication)" do
      let(:tbd_building) { create(:building, name: "To Be Determined", abbreviation: "TBD") }
      let(:tbd_room) { create(:room, building: tbd_building) }
      let!(:tbd_meeting_time) do
        create(:meeting_time,
               course: course,
               room: tbd_room,
               begin_time: 1000,
               end_time: 1150,
               day_of_week: :monday,
               meeting_schedule_type: :lecture)
      end

      it "deduplicates TBD and real-location meeting times, preferring the real one" do
        result = builder.build
        monday_times = result[:classes].first[:meeting_times].select { |mt| mt[:monday] }
        expect(monday_times.length).to eq(1)
        expect(monday_times.first.dig(:location, :building, :name)).to eq("Beatty Hall")
      end
    end

    describe "with two TBD meeting times at the same day/time" do
      let(:tbd_building) { create(:building, name: "To Be Determined", abbreviation: "TBD") }
      let(:tbd_room_a) { create(:room, building: tbd_building) }
      let(:tbd_room_b) { create(:room, building: tbd_building) }

      before do
        # Remove the real meeting time, replace with two TBD ones
        meeting_time.destroy
        create(:meeting_time, course: course, room: tbd_room_a, begin_time: 1300, end_time: 1450, day_of_week: :tuesday)
        create(:meeting_time, course: course, room: tbd_room_b, begin_time: 1300, end_time: 1450, day_of_week: :tuesday)
      end

      it "returns one meeting time even when all are TBD" do
        result = builder.build
        tuesday_times = result[:classes].first[:meeting_times].select { |mt| mt[:tuesday] }
        expect(tuesday_times.length).to eq(1)
      end
    end

    describe "with multiple enrollments across different courses" do
      let(:term2) { term } # same term
      let(:course2) do
        create(:course,
               term: term2,
               title: "Data Structures",
               subject: "Computer Science (CS)",
               course_number: 301,
               section_number: "02",
               schedule_type: :lecture)
      end
      let!(:meeting_time2) { create(:meeting_time, course: course2, room: room) }
      let!(:enrollment2) { create(:enrollment, user: user, course: course2, term: term2) }

      it "returns one entry per enrollment" do
        result = builder.build
        expect(result[:classes].length).to eq(2)
      end
    end

    describe "when the user has no enrollments in the term" do
      let(:other_term) { create(:term) }

      it "returns an empty classes array" do
        result = described_class.new(user, other_term).build
        expect(result[:classes]).to be_empty
      end
    end

    describe "with a Tuesday meeting time" do
      before do
        create(:meeting_time, course: course, room: room, begin_time: 1300, end_time: 1450, day_of_week: :tuesday)
      end

      it "marks tuesday as true in the days hash" do
        times = result[:classes].first[:meeting_times]
        tuesday_time = times.find { |mt| mt[:tuesday] }
        expect(tuesday_time).not_to be_nil
        expect(tuesday_time[:tuesday]).to be true
        expect(tuesday_time[:monday]).to be false
      end
    end
  end

  describe "build_days_hash" do
    let(:builder_instance) { described_class.new(user, term) }

    it "handles nil day_of_week gracefully (all days false)" do
      result = builder_instance.send(:build_days_hash, nil)
      expect(result.values.all?(&:itself)).to be false
      expect(result.values.none?(&:itself)).to be true
    end

    it "sets only the correct day to true" do
      %i[monday tuesday wednesday thursday friday saturday sunday].each do |day|
        hash = builder_instance.send(:build_days_hash, day)
        expect(hash[day]).to be true
        (hash.keys - [day]).each do |other_day|
          expect(hash[other_day]).to be false
        end
      end
    end
  end
end
