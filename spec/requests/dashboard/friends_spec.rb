# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Friends", type: :request do
  def create_user(first_name)
    create(:user, first_name: first_name)
  end

  # The model refuses a past expiry date, and time travel ends the sign-in
  # session, so move the date into the past without validation.
  def expire!(friendship)
    friendship.update_column(:expires_at, 1.minute.ago)
  end

  include ActiveJob::TestHelper

  let(:current_user) { create(:user, :with_processed_courses, first_name: "Ada") }
  let(:other_user)   { create_user("Grace") }

  before { sign_in current_user }

  after { Flipper.disable(FlipperFlags::FRIEND_EXPIRY) }

  describe "POST /dashboard/friends" do
    it "creates a pending request to the given public id" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.to change(Friendship, :count).by(1)

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:notice]).to eq("Friend request sent to Grace.")

      friendship = Friendship.last
      expect(friendship.requester).to eq(current_user)
      expect(friendship.addressee).to eq(other_user)
      expect(friendship).to be_pending
    end

    it "emails the requestee" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.to have_enqueued_mail(FriendshipMailer, :request_received)
    end

    it "reports an unknown user" do
      expect {
        post dashboard_friends_path, params: { friend_id: "usr_doesnotexist" }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("User not found.")
    end

    it "refuses a request to yourself" do
      expect {
        post dashboard_friends_path, params: { friend_id: current_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You can't add yourself.")
    end

    it "refuses a second request to the same user" do
      create(:friendship, requester: current_user, addressee: other_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end

    it "refuses a request when the other user already sent one" do
      create(:friendship, requester: other_user, addressee: current_user)

      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("You already have a request or friendship with Grace.")
    end
  end

  describe "POST /dashboard/friends with an end date" do
    let(:end_date) { 10.days.from_now.to_date }

    it "refuses an end date while the flag is off" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id, expires_on: end_date.iso8601 }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("Temporary friendships are not available.")
    end

    context "with the flag on" do
      before { Flipper.enable_actor(FlipperFlags::FRIEND_EXPIRY, current_user) }

      it "ends the friendship at the end of the chosen day" do
        post dashboard_friends_path, params: { friend_id: other_user.public_id, expires_on: end_date.iso8601 }

        expect(flash[:notice]).to eq("Friend request sent to Grace.")
        expect(Friendship.last.expires_at).to be_within(1.second).of(end_date.in_time_zone.end_of_day)
      end

      it "sends a permanent request when the end date is empty" do
        post dashboard_friends_path, params: { friend_id: other_user.public_id, expires_on: "" }

        expect(Friendship.last.expires_at).to be_nil
      end

      it "refuses an end date that is today or earlier" do
        expect {
          post dashboard_friends_path, params: { friend_id: other_user.public_id, expires_on: 1.day.ago.to_date.iso8601 }
        }.not_to change(Friendship, :count)

        expect(flash[:alert]).to eq("Pick an end date after today.")
      end

      it "refuses a value that is not a date" do
        post dashboard_friends_path, params: { friend_id: other_user.public_id, expires_on: "soon" }

        expect(flash[:alert]).to eq("Pick a valid end date.")
      end
    end
  end

  describe "PATCH /dashboard/friends/:id/expiry" do
    let!(:friendship) { create(:friendship, :accepted, :temporary, requester: other_user, addressee: current_user) }

    it "refuses the change while the flag is off" do
      patch expiry_dashboard_friend_path(other_user.public_id), params: { permanent: "1" }

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload.expires_at).to be_present
    end

    context "with the flag on" do
      before { Flipper.enable_actor(FlipperFlags::FRIEND_EXPIRY, current_user) }

      it "only proposes a later end date, and keeps the current one" do
        current  = friendship.expires_at
        new_date = 60.days.from_now.to_date

        expect {
          patch expiry_dashboard_friend_path(other_user.public_id), params: { expires_on: new_date.iso8601 }
        }.to have_enqueued_mail(FriendshipMailer, :expiry_changed)

        expect(flash[:notice]).to eq("You proposed a new end date. Grace must accept it before it applies.")
        friendship.reload
        expect(friendship.expires_at).to eq(current)
        expect(friendship.proposed_expires_at).to eq(
          ActiveSupport::TimeZone["America/New_York"].local(new_date.year, new_date.month, new_date.day, 23, 59, 59)
        )
      end

      it "does not make the friendship permanent alone, but proposes it" do
        patch expiry_dashboard_friend_path(other_user.public_id), params: { permanent: "Propose permanent" }

        expect(flash[:notice]).to eq("You proposed a new end date. Grace must accept it before it applies.")
        expect(friendship.reload.expires_at).to be_present
        expect(friendship.proposed_permanent).to be(true)
      end

      it "applies a sooner end date at once, at the end of that day in New York" do
        new_date = 3.days.from_now.to_date

        patch expiry_dashboard_friend_path(other_user.public_id), params: { expires_on: new_date.iso8601 }

        expect(flash[:notice]).to eq("Your friendship with Grace now ends on #{new_date.to_fs(:long)}.")
        expect(friendship.reload.expires_at).to eq(
          ActiveSupport::TimeZone["America/New_York"].local(new_date.year, new_date.month, new_date.day, 23, 59, 59)
        )
      end

      it "says when the date did not change" do
        friendship.update!(expires_at: 5.days.from_now.to_date.in_time_zone.end_of_day.change(usec: 0))

        patch expiry_dashboard_friend_path(other_user.public_id), params: { expires_on: 5.days.from_now.to_date.iso8601 }

        expect(flash[:notice]).to eq("The end date did not change.")
      end

      it "lets the requester change a pending request" do
        stranger = create_user("Alan")
        request  = create(:friendship, requester: current_user, addressee: stranger)

        patch expiry_dashboard_friend_path(stranger.public_id), params: { expires_on: 5.days.from_now.to_date.iso8601 }

        expect(request.reload.expires_at).to be_present
      end

      it "refuses a date in the past" do
        patch expiry_dashboard_friend_path(other_user.public_id), params: { expires_on: 1.day.ago.to_date.iso8601 }

        expect(flash[:alert]).to eq("Pick an end date after today.")
      end

      it "refuses a value that is not a date" do
        patch expiry_dashboard_friend_path(other_user.public_id), params: { expires_on: "" }

        expect(flash[:alert]).to eq("Pick a valid end date.")
      end

      it "refuses a user who is not a friend" do
        patch expiry_dashboard_friend_path(create_user("Alan").public_id), params: { permanent: "1" }

        expect(flash[:alert]).to eq("Friend not found.")
      end
    end
  end

  describe "POST /dashboard/friends/:id/accept_expiry and decline_expiry" do
    let!(:friendship) { create(:friendship, :accepted, :temporary, requester: other_user, addressee: current_user) }

    it "refuses while the flag is off" do
      friendship.change_expiry!(to: nil, by: other_user)

      post accept_expiry_dashboard_friend_path(other_user.public_id)

      expect(flash[:alert]).to eq("Friend not found.")
      expect(friendship.reload.expires_at).to be_present
    end

    context "with the flag on" do
      before { Flipper.enable_actor(FlipperFlags::FRIEND_EXPIRY, current_user) }

      it "accepts the friend's permanent proposal" do
        friendship.change_expiry!(to: nil, by: other_user)

        post accept_expiry_dashboard_friend_path(other_user.public_id)

        expect(flash[:notice]).to eq("Grace is now a permanent friend.")
        expect(friendship.reload.expires_at).to be_nil
      end

      it "accepts the friend's proposed date" do
        later = 30.days.from_now.change(usec: 0)
        friendship.change_expiry!(to: later, by: other_user)

        post accept_expiry_dashboard_friend_path(other_user.public_id)

        expect(flash[:notice]).to eq("Your friendship with Grace now ends on #{later.to_date.to_fs(:long)}.")
        expect(friendship.reload.expires_at).to eq(later)
      end

      it "refuses the proposer" do
        friendship.change_expiry!(to: nil, by: current_user)

        post accept_expiry_dashboard_friend_path(other_user.public_id)

        expect(friendship.reload.expires_at).to be_present
        expect(flash[:alert]).to be_present
      end

      it "declines the friend's proposal and keeps the date" do
        friendship.change_expiry!(to: nil, by: other_user)

        post decline_expiry_dashboard_friend_path(other_user.public_id)

        expect(flash[:notice]).to eq("The proposal is closed. The end date did not change.")
        expect(friendship.reload.expiry_proposal?).to be(false)
        expect(friendship.expires_at).to be_present
      end

      it "shows the proposal with Accept and Decline to the other user" do
        friendship.change_expiry!(to: nil, by: other_user)

        get dashboard_friends_path

        expect(response.body).to include("Grace proposed a permanent friendship.")
        expect(response.body).to include(accept_expiry_dashboard_friend_path(other_user.public_id))
      end

      it "shows Withdraw, not Accept, to the proposer" do
        friendship.change_expiry!(to: nil, by: current_user)

        get dashboard_friends_path

        expect(response.body).to include("You proposed a permanent friendship.")
        expect(response.body).not_to include(accept_expiry_dashboard_friend_path(other_user.public_id))
        expect(response.body).to include(decline_expiry_dashboard_friend_path(other_user.public_id))
      end

      it "shows the end date controls on the requests page" do
        create(:friendship, :temporary, requester: create_user("Alan"), addressee: current_user)

        get requests_dashboard_friends_path

        expect(response.body).to include("Set end date")
      end
    end
  end

  describe "GET /dashboard/friends with expiry" do
    it "shows the end date of a temporary friend" do
      friendship = create(:friendship, :accepted, :temporary, requester: current_user, addressee: other_user)

      get dashboard_friends_path

      expect(response.body).to include("Ends on #{friendship.expires_at.to_date.to_fs(:long)}")
    end

    it "shows the end date controls only with the flag on" do
      create(:friendship, :accepted, :temporary, requester: current_user, addressee: other_user)

      get dashboard_friends_path
      expect(response.body).not_to include("Propose permanent")
      expect(response.body).not_to include("End date (optional)")

      Flipper.enable_actor(FlipperFlags::FRIEND_EXPIRY, current_user)
      get dashboard_friends_path
      expect(response.body).to include("Propose permanent")
      expect(response.body).to include("End date (optional)")
    end

    it "leaves out a friend after the end date, and refuses their schedule" do
      expire!(create(:friendship, :accepted, :temporary, requester: current_user, addressee: other_user))

      get dashboard_friends_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No friends yet.")
      expect(response.body).not_to include(dashboard_friend_path(other_user.public_id))

      get dashboard_friend_path(other_user.public_id)
      expect(flash[:alert]).to eq("Friend not found.")
    end

    it "shows the end date on a request and hides an expired request" do
      request = create(:friendship, :temporary, requester: other_user, addressee: current_user)

      get requests_dashboard_friends_path
      expect(response.body).to include("Ends on #{request.expires_at.to_date.to_fs(:long)}")

      expire!(request)
      get requests_dashboard_friends_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No incoming requests.")
    end
  end

  describe "GET /dashboard/friends" do
    it "links each friend to their schedule" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)

      get dashboard_friends_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(dashboard_friend_path(other_user.public_id))
    end
  end

  describe "GET /dashboard/friends/requests" do
    # The show route would also match this path, so this guards the route order.
    it "still renders the requests page" do
      get requests_dashboard_friends_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /dashboard/friends/:id" do
    let(:term)   { create(:term) }
    let(:course) { create(:course, term: term, subject: "MATH", course_number: 2300, title: "Linear Algebra") }

    before do
      create(:course_meeting_time, course: course)
      create(:enrollment, user: other_user, course: course)
    end

    it "shows an accepted friend's courses" do
      create(:friendship, :accepted, requester: other_user, addressee: current_user)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape("#{other_user.full_name}'s Schedule"))
      expect(response.body).to include("MATH 2300")
      expect(response.body).to include("Linear Algebra")
    end

    it "keeps the week navigation on the friend's page" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)

      get dashboard_friend_path(other_user.public_id),
          params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        ERB::Util.html_escape(dashboard_friend_path(other_user.public_id, view: "week", term_uid: term.uid, week_start: "2026-09-21"))
      )
      expect(response.body).to include("MATH 2300")
    end

    it "does not show the signed-in user's own courses" do
      create(:friendship, :accepted, requester: current_user, addressee: other_user)
      own_course = create(:course, term: term, subject: "HIST", course_number: 1100)
      create(:enrollment, user: current_user, course: own_course)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list" }

      expect(response.body).to include("MATH 2300")
      expect(response.body).not_to include("HIST 1100")
    end

    it "refuses a user with only a pending request" do
      create(:friendship, requester: current_user, addressee: other_user)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:alert]).to eq("Friend not found.")
    end

    it "refuses a user who is not a friend" do
      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:alert]).to eq("Friend not found.")
    end
  end

  describe "GET /dashboard/friends/:id with availability-only sharing" do
    let(:term)   { create(:term) }
    let(:course) { create(:course, term: term, subject: "MATH", course_number: 2300, title: "Linear Algebra") }
    let!(:friendship) { create(:friendship, :accepted, requester: current_user, addressee: other_user) }

    before do
      create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 900, end_time: 1015)
      create(:enrollment, user: other_user, course: course)
    end

    after { Flipper.disable(FlipperFlags::FRIENDS_AVAILABILITY_ONLY) }

    it "shows busy blocks and no courses when the friend shares only availability" do
      friendship.update_visibility_for!(other_user, :availability_only)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list", week_start: "2026-10-05" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape("#{other_user.full_name}'s Availability"))
      expect(response.body).to include("Busy 09:00 to 10:15")
      expect(response.body).not_to include("MATH 2300")
      expect(response.body).not_to include("Linear Algebra")
    end

    it "still shows the friend's courses when only the signed-in user limits sharing" do
      friendship.update_visibility_for!(current_user, :availability_only)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid, view: "list" }

      expect(response.body).to include("Linear Algebra")
    end

    it "hides the sharing form while the flag is off" do
      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response.body).not_to include(visibility_dashboard_friend_path(other_user.public_id))
    end

    it "shows the sharing form with the flag on" do
      Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)

      get dashboard_friend_path(other_user.public_id), params: { term_uid: term.uid }

      expect(response.body).to include(visibility_dashboard_friend_path(other_user.public_id))
      expect(response.body).to include("Only when I am busy")
    end
  end

  describe "PATCH /dashboard/friends/:id/visibility" do
    let!(:friendship) { create(:friendship, :accepted, requester: other_user, addressee: current_user) }

    after { Flipper.disable(FlipperFlags::FRIENDS_AVAILABILITY_ONLY) }

    it "answers 404 while the flag is off" do
      patch visibility_dashboard_friend_path(other_user.public_id), params: { visibility: "availability_only" }

      expect(response).to have_http_status(:not_found)
      expect(friendship.reload).to be_addressee_full
    end

    context "with the flag on" do
      before { Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user) }

      it "sets the signed-in user's own level" do
        patch visibility_dashboard_friend_path(other_user.public_id), params: { visibility: "availability_only" }

        expect(response).to redirect_to(dashboard_friend_path(other_user.public_id))
        expect(flash[:notice]).to eq("Grace can see only when you are busy.")
        expect(friendship.reload).to be_addressee_availability_only
        expect(friendship).to be_requester_full
      end

      it "sets the level back to full" do
        friendship.update_visibility_for!(current_user, :availability_only)

        patch visibility_dashboard_friend_path(other_user.public_id), params: { visibility: "full" }

        expect(flash[:notice]).to eq("Grace can see your full schedule.")
        expect(friendship.reload).to be_addressee_full
      end

      it "refuses an unknown level" do
        patch visibility_dashboard_friend_path(other_user.public_id), params: { visibility: "hidden" }

        expect(flash[:alert]).to eq("Choose a valid sharing level.")
        expect(friendship.reload).to be_addressee_full
      end

      it "refuses a user who is not a friend" do
        patch visibility_dashboard_friend_path(create_user("Alan").public_id), params: { visibility: "full" }

        expect(flash[:alert]).to eq("Friend not found.")
      end
    end
  end

  describe "POST /dashboard/friends/:id/accept" do
    it "accepts an incoming request" do
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      post accept_dashboard_friend_path(friendship.id)

      expect(response).to redirect_to(dashboard_friends_path)
      expect(flash[:notice]).to eq("Grace added as a friend.")
      expect(friendship.reload).to be_accepted
      expect(current_user.friends).to include(other_user)
    end

    it "does not accept a request addressed to somebody else" do
      third      = create_user("Alan")
      friendship = create(:friendship, requester: other_user, addressee: third)

      post accept_dashboard_friend_path(friendship.id)

      expect(flash[:alert]).to eq("Request not found.")
      expect(friendship.reload).to be_pending
    end
  end

  describe "choosing a level when sending or accepting a request" do
    after { Flipper.disable(FlipperFlags::FRIENDS_AVAILABILITY_ONLY) }

    it "sets the sender's side when the flag is on" do
      Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)

      post dashboard_friends_path, params: { friend_id: other_user.public_id, visibility: "availability_only" }

      expect(Friendship.last).to be_requester_availability_only
      expect(Friendship.last).to be_addressee_full
    end

    it "refuses the level and sends no request while the flag is off" do
      expect {
        post dashboard_friends_path, params: { friend_id: other_user.public_id, visibility: "availability_only" }
      }.not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("Choose a valid sharing level.")
    end

    it "sets the accepting user's side when the flag is on" do
      Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      post accept_dashboard_friend_path(friendship.id), params: { visibility: "availability_only" }

      expect(friendship.reload).to be_accepted
      expect(friendship).to be_addressee_availability_only
      expect(friendship).to be_requester_full
    end

    it "leaves the request pending while the flag is off" do
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      post accept_dashboard_friend_path(friendship.id), params: { visibility: "availability_only" }

      expect(friendship.reload).to be_pending
    end

    it "shows the level choice on the requests page only with the flag on" do
      create(:friendship, requester: other_user, addressee: current_user)

      get requests_dashboard_friends_path
      expect(response.body).not_to include("Share only when I am busy")

      Flipper.enable_actor(FlipperFlags::FRIENDS_AVAILABILITY_ONLY, current_user)
      get requests_dashboard_friends_path
      expect(response.body).to include("Share only when I am busy")
    end
  end

  describe "POST /dashboard/friends/:id/decline" do
    it "deletes an incoming request" do
      friendship = create(:friendship, requester: other_user, addressee: current_user)

      expect { post decline_dashboard_friend_path(friendship.id) }
        .to change(Friendship, :count).by(-1)

      expect(flash[:notice]).to eq("Request declined.")
    end
  end

  describe "DELETE /dashboard/friends/:id" do
    it "removes an accepted friend" do
      create(:friendship, :accepted, requester: other_user, addressee: current_user)

      expect { delete dashboard_friend_path(other_user.public_id) }
        .to change(Friendship, :count).by(-1)

      expect(flash[:notice]).to eq("Grace removed.")
      expect(current_user.friends).to be_empty
    end

    it "reports a user who is not a friend" do
      expect { delete dashboard_friend_path(other_user.public_id) }
        .not_to change(Friendship, :count)

      expect(flash[:alert]).to eq("Friend not found.")
    end
  end
end
