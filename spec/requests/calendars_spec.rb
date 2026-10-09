# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /calendar/:calendar_token", type: :request do
  let!(:term) { create(:term, uid: 202710) }

  let(:class_details) do
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      credit_hours: 4,
      schedule_type: "Lecture (LEC)",
      meeting_times: [
        {
          "building"             => "IRAH",
          "building_description" => "Ira Allen Hall",
          "room"                 => "112",
          "startDate"            => "09/08/2026",
          "endDate"              => "12/15/2026",
          "startTime"            => "1300",
          "endTime"              => "1445",
          "days"                 => { "monday" => true }
        }
      ]
    }
  end

  before { allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(class_details) }

  def student_in(crns)
    user = create(:user)
    Courses::Processor.new(crns.map { |crn| { crn: crn, term: "202710", courseNumber: "2000" } }, user).call
    user
  end

  def final_for(crn, date)
    create(:final_exam, term: term, crn: crn, course: Course.find_by!(crn: crn, term: term), exam_date: date)
  end

  def recurrence_end_by_crn
    events = Icalendar::Calendar.parse(response.body).first.events
    events.filter_map { |e|
      crn = e.uid.to_s[/\Acourse-(\d+)-meeting-/, 1]
      [ crn, e.rrule.first.until.to_time.in_time_zone("America/New_York").to_date ] if crn
    }.to_h
  end

  def final_exam_queries
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].include?(%("final_exams")) && !payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  it "ends each class the day before its own final" do
    user = student_in(%w[11111 22222 33333])
    final_for(11111, Date.new(2026, 12, 10))
    final_for(22222, Date.new(2026, 12, 3))

    get "/calendar/#{user.calendar_token}"

    expect(response).to have_http_status(:ok)
    expect(recurrence_end_by_crn).to eq(
      "11111" => Date.new(2026, 12, 9),
      "22222" => Date.new(2026, 12, 2),
      # No final of its own, so it stops before the term's first final.
      "33333" => Date.new(2026, 12, 2)
    )
  end

  it "looks up finals with the same number of queries for three classes as for one" do
    one   = student_in(%w[11111])
    three = student_in(%w[22222 33333 44444])
    %w[11111 22222 33333 44444].each_with_index { |crn, i| final_for(crn, Date.new(2026, 12, 3 + i)) }

    one_count   = final_exam_queries { get "/calendar/#{one.calendar_token}" }
    three_count = final_exam_queries { get "/calendar/#{three.calendar_token}" }

    expect(response).to have_http_status(:ok)
    expect(three_count).to eq(one_count)
  end

  describe "HTTP caching" do
    include ActiveSupport::Testing::TimeHelpers

    it "sends the same ETag for the same data, even at a later time" do
      user = student_in(%w[11111])

      get "/calendar/#{user.calendar_token}"
      first_etag = response.headers["ETag"]
      travel 5.minutes do
        get "/calendar/#{user.calendar_token}"
      end

      expect(first_etag).to be_present
      expect(response.headers["ETag"]).to eq(first_etag)
    end

    it "answers 304 with no body when the client already has the current feed" do
      user = student_in(%w[11111])
      get "/calendar/#{user.calendar_token}"

      get "/calendar/#{user.calendar_token}", headers: { "If-None-Match" => response.headers["ETag"] }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(response.headers["Cache-Control"]).to include("max-age=3600")
    end

    it "sends the full feed with a new ETag after a class changes" do
      user = student_in(%w[11111])
      get "/calendar/#{user.calendar_token}"
      old_etag = response.headers["ETag"]

      travel 1.minute do
        Course.find_by!(crn: 11111).update!(title: "Advanced Data Structures")
        get "/calendar/#{user.calendar_token}", headers: { "If-None-Match" => old_etag }
      end

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(old_etag)
      expect(response.body).to include("Advanced Data Structures")
    end
  end

  # A calendar client keeps its copy of an event until LAST-MODIFIED or
  # SEQUENCE goes up. Settings and rows outside the course and meeting time
  # also change the event, so they must move these fields too.
  describe "LAST-MODIFIED of a class event" do
    include ActiveSupport::Testing::TimeHelpers

    let!(:user) { student_in(%w[11111]) }
    let(:meeting_time) { Course.find_by!(crn: 11111).meeting_times.first }

    def class_event
      Icalendar::Calendar.parse(response.body).first.events.find { |e| e.uid.to_s.start_with?("course-11111-") }
    end

    # Fetches the feed, makes the change two minutes later, and fetches it
    # again. Returns the event and the ETag from before and after the change.
    def around_change
      get "/calendar/#{user.calendar_token}"
      before = [ class_event, response.headers["ETag"] ]

      travel 2.minutes do
        yield
        get "/calendar/#{user.calendar_token}"
      end

      [ before, [ class_event, response.headers["ETag"] ] ]
    end

    def expect_newer((old_event, old_etag), (new_event, new_etag))
      expect(new_event.last_modified.to_time).to be > old_event.last_modified.to_time
      expect(new_event.dtstamp.to_time).to eq(new_event.last_modified.to_time)
      expect(new_event.sequence.to_i).to be > old_event.sequence.to_i
      expect(new_etag).not_to eq(old_etag)
    end

    it "goes up when a calendar preference changes" do
      preference = create(:calendar_preference, user: user, title_template: "{{title}}")

      before, after = around_change { preference.update!(title_template: "{{course_code}} {{title}}") }

      expect_newer(before, after)
    end

    it "goes up when the user adds a calendar preference" do
      before, after = around_change { create(:calendar_preference, user: user, color_id: "#a4bdfc") }

      expect_newer(before, after)
    end

    it "goes up when the preference for the event changes" do
      preference = create(:event_preference, user: user, preferenceable: meeting_time, title_template: "{{title}}")

      before, after = around_change { preference.update!(color_id: "#a4bdfc") }

      expect_newer(before, after)
    end

    it "goes up when a holiday removes a class day" do
      before, after = around_change do
        create(:university_calendar_event, category: "holiday", summary: "Holiday",
                                           start_time: Time.zone.local(2026, 10, 12), end_time: Time.zone.local(2026, 10, 12, 23, 59))
      end

      expect_newer(before, after)
      expect(after.first.exdate.flatten.map(&:to_date)).to include(Date.new(2026, 10, 12))
    end

    it "goes up when the class moves to another room" do
      new_room = create(:room)

      before, after = around_change do
        meeting_time.meeting_time_rooms.destroy_all
        create(:course_meeting_time_room, meeting_time: meeting_time, room: new_room)
      end

      expect_newer(before, after)
    end

    it "goes up when a building changes its name" do
      building = meeting_time.rooms.first.building

      before, after = around_change { building.update!(name: "New Hall") }

      expect_newer(before, after)
    end
  end
end
