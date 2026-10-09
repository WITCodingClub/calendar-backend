# frozen_string_literal: true

require "rails_helper"

# Dashboard::ApplicationController runs verify_authorized after every action. A
# dashboard action that never calls authorize or skip_authorization raises
# Pundit::AuthorizationNotPerformedError, and the user gets a 500. This spec
# requests every dashboard route as a signed-in student and fails on that
# error. Each route gets a real record of the user for its :id param, so the
# request gets past the record lookup and reaches the authorization call. A
# lookup that halts the request also skips the after_action, so a fake id would
# hide a missing authorize.
RSpec.describe "Dashboard authorization", type: :request do
  dashboard_routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    next unless controller&.start_with?("dashboard/")

    verb = route.verb.split("|").first.presence || "GET"
    path = route.path.spec.to_s.delete_suffix("(.:format)")

    { controller: controller, action: route.defaults[:action], verb: verb, path: path }
  end

  # Turn on every flag, so the flagged actions run instead of answering 404.
  flags = FeatureFlags.constants.map { |name| FeatureFlags.const_get(name) }.grep(Symbol)

  let(:user)   { create(:user, :with_processed_courses) }
  let(:friend) { create(:user) }

  # The value for each param, per controller. Each one is a record that the
  # signed-in user owns, so the lookup finds it.
  let(:ids) do
    {
      "dashboard/calendar_preferences"  => { id: -> { "global" } },
      "dashboard/connected_accounts"    => { id: -> { create(:oauth_credential, user: user).public_id } },
      "dashboard/sign_in_identities"    => { id: -> { create(:sign_in_identity, user: user).id } },
      "dashboard/friend_groups"         => { id: -> { create(:friend_group, user: user).public_id } },
      "dashboard/friend_group_members"  => { friend_group_id: -> { create(:friend_group, user: user).public_id },
                                             id: -> { friend.public_id } },
      "dashboard/friends/requests"      => { id: -> { create(:friendship, addressee: user).id } },
      "dashboard/friends"               => { id: -> { friend.public_id } },
      "dashboard/meeting_links"         => { id: -> { create(:meeting_link, user: user).public_id } }
    }
  end

  def path_for(route)
    params = ids.fetch(route[:controller], {})

    route[:path].gsub(/:(\w+)/) do
      param = Regexp.last_match(1)
      param == "friend_id" ? friend.public_id : params.fetch(param.to_sym).call.to_s
    end
  end

  before do
    create(:friendship, :accepted, requester: friend, addressee: user)
    flags.each { |flag| Flipper.enable(flag) }
    sign_in user
  end

  # The Flipper cache is not part of the test transaction.
  after { flags.each { |flag| Flipper.disable(flag) } }

  it "runs verify_authorized after every dashboard action" do
    callbacks = Dashboard::ApplicationController._process_action_callbacks
    expect(callbacks.any? { |callback| callback.kind == :after && callback.filter == :verify_authorized }).to be(true)
  end

  it "finds the dashboard routes" do
    expect(dashboard_routes.size).to be > 30
  end

  dashboard_routes.each do |route|
    it "authorizes #{route[:verb]} #{route[:path]} (#{route[:controller]}##{route[:action]})" do
      path = path_for(route)

      begin
        process route[:verb].downcase.to_sym, path
      rescue Pundit::AuthorizationNotPerformedError
        raise
      rescue Exception # rubocop:disable Lint/RescueException
        # A GET page must render. A write action can fail after it authorizes,
        # for example on a missing param, so only a missing authorization
        # fails it.
        raise if route[:verb] == "GET"
      end
    end
  end
end
