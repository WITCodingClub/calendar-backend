# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilterMeetingLinkTokens do
  def request_for(path, method: "GET")
    ActionDispatch::Request.new(Rack::MockRequest.env_for(path, method: method))
  end

  def started_line(request)
    Rails::Rack::Logger.new(->(_env) { [ 200, {}, [] ] }).send(:started_request_message, request)
  end

  it "hides the token in the logged path of each meeting link route" do
    expect(started_line(request_for("/meet/synthetic-secret-token"))).to include('"/meet/[FILTERED]"')
    expect(started_line(request_for("/meet/synthetic-secret-token", method: "POST"))).to include('Started POST "/meet/[FILTERED]"')
    expect(started_line(request_for("/meet/synthetic-secret-token/sign_in"))).to include('"/meet/[FILTERED]/sign_in"')
    expect(started_line(request_for("/meet/synthetic-secret-token?date=2026-10-08"))).to include('"/meet/[FILTERED]?date=2026-10-08"')
  end

  it "keeps the real path for routing" do
    request = request_for("/meet/synthetic-secret-token")

    expect(request.filtered_path).to eq("/meet/[FILTERED]")
    expect(request.path).to eq("/meet/synthetic-secret-token")
  end

  it "leaves other paths alone" do
    expect(request_for("/api/meeting_links/mln_abc").filtered_path).to eq("/api/meeting_links/mln_abc")
    expect(request_for("/meeting").filtered_path).to eq("/meeting")
  end

  it "hides a redirect to a meeting link page" do
    expect(Rails.application.config.filter_redirect).to include(%r{/meet/})
  end
end
