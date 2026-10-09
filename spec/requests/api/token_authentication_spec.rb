# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API token authentication", type: :request do
  let(:user) { create(:user) }

  def user_queries(&block)
    queries = []
    counter = lambda do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(/\ASELECT .* FROM "users" WHERE "users"\."id" = /)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    queries
  end

  # The Rack::Attack privileged-users safelist loads the user of the token.
  # The controller uses that record and does not load the user again (#712).
  it "loads the signed-in user once for each request" do
    queries = user_queries { get "/api/user/preferences/version", headers: auth_headers_for(user) }

    expect(response).to have_http_status(:ok)
    expect(queries.size).to eq(1)
  end
end
