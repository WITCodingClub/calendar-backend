# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/meeting_times/preferences", type: :request do
  let(:user) { create(:user) }
  let!(:term) { create(:term, uid: 202710) }
  let(:headers) { auth_headers_for(user) }

  def class_details(room)
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      credit_hours: 4,
      schedule_type: "Lecture (LEC)",
      faculty: [ { "displayName" => "Elijah Sanderson", "emailAddress" => "sandersone1@wit.edu", "primaryIndicator" => true } ],
      meeting_times: [
        {
          "building"             => "IRAH",
          "building_description" => "Ira Allen Hall",
          "room"                 => room,
          "startDate"            => "09/08/2026",
          "endDate"              => "12/15/2026",
          "startTime"            => "1300",
          "endTime"              => "1445",
          "days"                 => { "monday" => true, "wednesday" => true }
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
    Course::MeetingTime.joins(:course).where(courses: { crn: crns }).order(:id).to_a
  end

  def json = JSON.parse(response.body)

  def query_count
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:cached] || payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  before { Flipper.enable(FlipperFlags::V1) }

  after { Flipper.disable(FlipperFlags::V1) }

  it "answers for each meeting time exactly as the single endpoint does" do
    meeting_times = enroll_in(%w[11111 22222])
    create(:calendar_preference, user: user, title_template: "{{course_code}} {{title}}", color_id: 5)
    create(:event_preference, user: user, preferenceable: meeting_times.first, title_template: "Mine: {{title}}")

    singles = meeting_times.to_h do |mt|
      get "/api/meeting_times/#{mt.public_id}/preference", headers: headers
      [ mt.public_id, json ]
    end

    post "/api/meeting_times/preferences", params: { meeting_time_ids: meeting_times.map(&:public_id) }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["preferences"]).to eq(singles)
    expect(json["missing"]).to eq([])
    expect(json.dig("preferences", meeting_times.first.public_id, "preview", "title")).to eq("Mine: Data Structures")
  end

  it "runs the same number of queries for three classes as for one" do
    one   = enroll_in(%w[11111])
    three = enroll_in(%w[22222 33333 44444])

    # The first request of a session also records when it was last seen.
    post "/api/meeting_times/preferences", params: { meeting_time_ids: one.map(&:public_id) }, headers: headers, as: :json

    one_count = query_count do
      post "/api/meeting_times/preferences", params: { meeting_time_ids: one.map(&:public_id) }, headers: headers, as: :json
    end
    three_count = query_count do
      post "/api/meeting_times/preferences", params: { meeting_time_ids: three.map(&:public_id) }, headers: headers, as: :json
    end

    expect(json["preferences"].size).to eq(6)
    expect(three_count).to eq(one_count)
  end

  it "lists ids that match no meeting time instead of failing" do
    meeting_time = enroll_in(%w[11111]).first

    post "/api/meeting_times/preferences",
         params: { meeting_time_ids: [ meeting_time.public_id, "mtt_doesnotexist", "bld_#{meeting_time.hashid}" ] },
         headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["preferences"].keys).to eq([ meeting_time.public_id ])
    expect(json["missing"]).to eq([ "mtt_doesnotexist", "bld_#{meeting_time.hashid}" ])
  end

  it "accepts a database id, as the single endpoint does" do
    meeting_time = enroll_in(%w[11111]).first

    post "/api/meeting_times/preferences", params: { meeting_time_ids: [ meeting_time.id.to_s ] }, headers: headers, as: :json

    expect(json["preferences"].keys).to eq([ meeting_time.id.to_s ])
  end

  it "requires at least one id" do
    post "/api/meeting_times/preferences", params: { meeting_time_ids: [] }, headers: headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "refuses more ids than one request may carry" do
    ids = Array.new(Api::EventPreferencesController::MAX_BATCH_SIZE + 1) { |i| "mtt_#{i}" }

    post "/api/meeting_times/preferences", params: { meeting_time_ids: ids }, headers: headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "requires a signed-in user" do
    post "/api/meeting_times/preferences", params: { meeting_time_ids: [ "mtt_x" ] }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
