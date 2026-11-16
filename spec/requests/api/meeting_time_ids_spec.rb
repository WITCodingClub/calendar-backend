# frozen_string_literal: true

require "rails_helper"

# The meeting time endpoints take a public id, a bare hashid, or a database id
# (PublicIds.record_id). A hashid that starts with digits must find its own
# record, never the record whose id is those digits.
RSpec.describe "Meeting time ids in the preference endpoints", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  # A database id whose hashid starts with digits, and the id those digits name.
  let(:ids) do
    (900_000..).lazy.filter_map do |id|
      digits = Course::MeetingTime.encode_id(id)[/\A[1-9]\d*(?=[a-z])/]
      [ id, digits.to_i ] if digits
    end.first
  end
  let!(:target) { create(:course_meeting_time, id: ids.first, course: create(:course, title: "Target Course")) }
  let!(:decoy)  { create(:course_meeting_time, id: ids.last, course: create(:course, title: "Decoy Course")) }

  def title_of(body) = body.dig("templates", "title")

  it "finds a meeting time by its bare hashid" do
    get "/api/meeting_times/#{target.hashid}/preference", headers: headers

    expect(response).to have_http_status(:ok)
    expect(title_of(response.parsed_body)).to eq("Target Course")
  end

  it "finds the right meeting time for a hashid that starts with digits" do
    expect(target.hashid).to start_with(ids.last.to_s)

    get "/api/meeting_times/#{target.hashid}/preference", headers: headers

    expect(title_of(response.parsed_body)).to eq("Target Course")
  end

  it "reads the same hashid the same way in the batch endpoint" do
    post "/api/meeting_times/preferences", params: { meeting_time_ids: [ target.hashid ] }, headers: headers, as: :json

    expect(title_of(response.parsed_body.dig("preferences", target.hashid))).to eq("Target Course")
  end

  it "answers 404 for a digit-leading id that is not a hashid" do
    get "/api/meeting_times/#{decoy.id}abcxyz/preference", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
