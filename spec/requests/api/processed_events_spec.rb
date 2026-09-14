# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/user/processed_events", type: :request do
  let(:user) { User.create!(email: "events@wit.edu", password: "password123") }
  let!(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:headers) { auth_headers_for(user) }

  def class_details(room)
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
          "room"                 => room,
          "startDate"            => "09/08/2026",
          "endDate"              => "12/15/2026",
          "startTime"            => "1300",
          "endTime"              => "1445",
          "days"                 => { "monday" => true, "wednesday" => true, "friday" => true }
        }
      ]
    }
  end

  def enroll_in(crns)
    crns.each_with_index do |crn, index|
      allow(LeopardWebService).to receive(:get_class_details)
        .with(term: "202710", course_reference_number: crn)
        .and_return(class_details((100 + index).to_s))
    end

    CourseProcessorService.new(crns.map { |crn| { crn: crn, term: "202710", courseNumber: "2000" } }, user).call
  end

  def queries_for(table)
    count = 0
    counter = lambda do |*, payload|
      count += 1 if payload[:sql].include?(%("#{table}")) && !payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  it "loads rooms and buildings once, no matter how many classes there are" do
    enroll_in(%w[11111 22222 33333])

    room_queries = building_queries = nil
    room_queries = queries_for("rooms") do
      building_queries = queries_for("buildings") do
        post "/api/user/processed_events", params: { term_uid: term.uid }, headers: headers
      end
    end

    expect(response).to have_http_status(:ok)
    meeting_times = JSON.parse(response.body)["classes"].flat_map { |c| c["meeting_times"] }
    expect(meeting_times.length).to eq(9)
    expect(meeting_times.map { |mt| mt.dig("location", "building", "abbreviation") }.uniq).to eq([ "IRAH" ])
    expect(room_queries).to eq(1)
    expect(building_queries).to eq(1)
  end
end
