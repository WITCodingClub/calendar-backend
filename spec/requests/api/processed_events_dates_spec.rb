# frozen_string_literal: true

require "rails_helper"

# effective_end_date and excluded_dates give the extension the same cutoff and
# no-class dates that calendar sync uses (#903). The factory course runs from
# Tuesday 2026-09-08 to Tuesday 2026-12-15. The last Monday class is 2026-12-07,
# Study Day is 2026-12-08, and finals run 2026-12-09 to 2026-12-15.
RSpec.describe "Class end dates in processed events", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:term)    { create(:term) }

  let(:with_final)    { create(:course, term: term) }
  let(:without_final) { create(:course, term: term) }

  before do
    create(:university_calendar_event, category: "holiday", summary: "Indigenous Peoples Day",
                                       start_time: Time.zone.local(2026, 10, 12, 0, 0), end_time: Time.zone.local(2026, 10, 12, 23, 59))
    create(:university_calendar_event, term: term, category: "finals", summary: "Study Day",
                                       start_time: Time.zone.local(2026, 12, 8, 0, 0), end_time: Time.zone.local(2026, 12, 8, 23, 59))
    create(:university_calendar_event, term: term, category: "finals", summary: "Final Exam Period",
                                       start_time: Time.zone.local(2026, 12, 9, 0, 0), end_time: Time.zone.local(2026, 12, 15, 23, 59))
    create(:final_exam, course: with_final, term: term, exam_date: Date.new(2026, 12, 10))
  end

  def enroll(owner, course, day)
    create(:course_meeting_time, course: course, day_of_week: day)
    create(:enrollment, user: owner, course: course, term: term)
  end

  def meeting_times_by_crn
    response.parsed_body["classes"].to_h { |c| [ c["crn"], c["meeting_times"].sole ] }
  end

  shared_examples "class end dates" do
    it "ends every class before Study Day and lists the holidays on its meeting day" do
      enroll(owner, with_final, :monday)
      enroll(owner, without_final, :thursday)

      get path, params: { term_uid: term.uid }, headers: headers

      expect(response).to have_http_status(:ok)
      monday   = meeting_times_by_crn.fetch(with_final.crn)
      thursday = meeting_times_by_crn.fetch(without_final.crn)

      # The last Monday class is on the effective end date. Study Day, finals,
      # and dates after finals are after it.
      expect(monday["effective_end_date"]).to eq("2026-12-07")
      expect(monday["excluded_dates"]).to eq([ "2026-10-12" ])
      # A course without a linked final has the same cutoff.
      expect(thursday["effective_end_date"]).to eq("2026-12-07")
      expect(thursday["excluded_dates"]).to eq([])
      # The stored dates do not change.
      expect(Date.parse(monday["end_date"])).to eq(Date.new(2026, 12, 15))
    end

    it "returns the dates after finals have passed" do
      enroll(owner, without_final, :monday)

      travel_to Time.zone.local(2027, 1, 20, 12, 0) do
        get path, params: { term_uid: term.uid }, headers: auth_headers_for(user)
      end

      expect(response).to have_http_status(:ok)
      meeting_time = meeting_times_by_crn.fetch(without_final.crn)
      expect(meeting_time["effective_end_date"]).to eq("2026-12-07")
      expect(meeting_time["excluded_dates"]).to eq([ "2026-10-12" ])
    end
  end

  describe "GET /api/user/processed_events" do
    let(:owner) { user }
    let(:path)  { "/api/user/processed_events" }

    it_behaves_like "class end dates"
  end

  describe "GET /api/friends/:friend_id/processed_events" do
    let(:owner) { create(:user) }
    let(:path)  { "/api/friends/#{owner.public_id}/processed_events" }

    before { create(:friendship, :accepted, requester: user, addressee: owner) }

    it_behaves_like "class end dates"
  end
end
