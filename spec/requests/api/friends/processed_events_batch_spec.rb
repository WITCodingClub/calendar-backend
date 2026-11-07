# frozen_string_literal: true

require "rails_helper"

# POST /api/friends/processed_events gives the schedules of many friends in
# one request (#681). Each entry must match the single-friend route.
RSpec.describe "POST /api/friends/processed_events", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:term)    { create(:term) }
  let(:path)    { "/api/friends/processed_events" }

  def befriend(friend)
    create(:friendship, :accepted, requester: user, addressee: friend)
  end

  def enroll(owner, day: :monday)
    course = create(:course, term: term)
    meeting_time = create(:course_meeting_time, course: course, day_of_week: day)
    create(:enrollment, user: owner, course: course, term: term)
    meeting_time
  end

  def post_batch(friend_ids, term_uid: term.uid)
    post path, params: { term_uid: term_uid, friend_ids: friend_ids }, headers: headers, as: :json
  end

  def entries
    response.parsed_body["schedules"]
  end

  describe "readable friends" do
    let(:ada)   { create(:user) }
    let(:grace) { create(:user) }

    before do
      befriend(ada)
      create(:friendship, :accepted, requester: grace, addressee: user)

      # A holiday, a final exam, and each friend's own preferences, so the
      # recurrence lookups and the preference rows load for each friend.
      create(:university_calendar_event, category: "holiday", summary: "Indigenous Peoples Day",
                                         start_time: Time.zone.local(2026, 10, 12, 0, 0),
                                         end_time: Time.zone.local(2026, 10, 12, 23, 59))
      ada_class = enroll(ada)
      create(:final_exam, course: ada_class.course, term: term, exam_date: Date.new(2026, 12, 10))
      create(:calendar_preference, user: ada, title_template: "Ada: {{title}}")
      create(:event_preference, user: ada, preferenceable: ada_class, color_id: "11")
      enroll(grace, day: :wednesday)
      enroll(grace, day: :friday)
      create(:calendar_preference, user: grace, title_template: "Grace: {{title}}")
    end

    it "gives each friend the body of the single-friend route, in the order of friend_ids" do
      single = [ grace, ada ].to_h do |friend|
        get "/api/friends/#{friend.public_id}/processed_events", params: { term_uid: term.uid }, headers: headers
        [ friend.public_id, response.parsed_body ]
      end

      post_batch([ grace.public_id, ada.public_id ])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["term_uid"]).to eq(term.uid)
      expect(entries.pluck("friend_id")).to eq([ grace.public_id, ada.public_id ])
      entries.each { |entry| expect(entry.except("friend_id")).to eq(single.fetch(entry["friend_id"])) }
      expect(entries.first["classes"].size).to eq(2)
      expect(entries.last["classes"].sole["meeting_times"].sole["calendar_config"]["title"]).to start_with("Ada: ")
    end

    it "lists a repeated id once" do
      post_batch([ ada.public_id, ada.public_id ])

      expect(entries.pluck("friend_id")).to eq([ ada.public_id ])
    end

    it "gives an empty class list to a friend with no classes in the term" do
      other_term = create(:term)
      post_batch([ ada.public_id ], term_uid: other_term.uid)

      expect(entries.sole).to include("friend_id" => ada.public_id, "classes" => [])
    end
  end

  describe "friends the user cannot read" do
    it "gives AVAILABILITY_ONLY for a friend who shares only availability" do
      friend = create(:user)
      enroll(friend)
      befriend(friend).update_visibility_for!(friend, :availability_only)

      post_batch([ friend.public_id ])

      expect(response).to have_http_status(:ok)
      expect(entries.sole).to eq(
        "friend_id" => friend.public_id, "error" => "This friend shares only availability",
        "code" => "AVAILABILITY_ONLY", "visibility" => "availability_only"
      )
    end

    it "gives NOT_FRIENDS for a stranger, a pending request, an expired friendship, and an unknown id" do
      stranger = create(:user)
      pending  = create(:friendship, requester: user).addressee
      expired  = create(:user)
      befriend(expired).update_columns(expires_at: 1.minute.ago)

      ids = [ stranger.public_id, pending.public_id, expired.public_id, "usr_doesnotexist" ]
      post_batch(ids)

      expect(response).to have_http_status(:ok)
      expect(entries.pluck("friend_id")).to eq(ids)
      expect(entries.pluck("code")).to all(eq("NOT_FRIENDS"))
      expect(entries.map(&:keys)).to all(contain_exactly("friend_id", "error", "code"))
    end
  end

  describe "bad requests" do
    it "answers 400 without friend_ids" do
      post path, params: { term_uid: term.uid }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("friend_ids must be a list of friend ids")
    end

    it "answers 400 for an empty list or a list with a value that is not a string" do
      post_batch([])
      expect(response).to have_http_status(:bad_request)

      post_batch([ { id: "usr_x" } ])
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 400 for more than #{Api::Friends::SchedulesController::MAX_BATCH_FRIENDS} ids" do
      post_batch(Array.new(Api::Friends::SchedulesController::MAX_BATCH_FRIENDS + 1) { |i| "usr_#{i}" })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("friend_ids takes at most 100 ids")
    end

    it "answers 400 without term_uid and 404 for an unknown term" do
      post path, params: { friend_ids: [ "usr_x" ] }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)

      post_batch([ "usr_x" ], term_uid: "999999")
      expect(response).to have_http_status(:not_found)
    end
  end
end
