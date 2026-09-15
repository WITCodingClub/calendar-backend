# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::ExtensionEvents", type: :request do
  def count_for(event, version: "4.0.1", browser: "chrome")
    Yabeda.calendar.extension_events_total.get(event: event, version: version, browser: browser) || 0
  end

  def post_events(body)
    post "/api/extension_events", params: body, as: :json
  end

  describe "POST /api/extension_events" do
    it "counts a known event without a token or the beta flag" do
      expect { post_events(events: [ "schedule_import_succeeded" ], version: "4.0.1", browser: "chrome") }
        .to change { count_for("schedule_import_succeeded") }.by(1)

      expect(response).to have_http_status(:no_content)
    end

    it "counts an event once for each time it appears" do
      expect { post_events(events: %w[calendar_link_copied calendar_link_copied], version: "4.0.1", browser: "chrome") }
        .to change { count_for("calendar_link_copied") }.by(2)
    end

    it "ignores event names that are not on the list" do
      post_events(events: [ "made_up_event" ], version: "4.0.1", browser: "chrome")

      expect(response).to have_http_status(:no_content)
      expect(count_for("made_up_event")).to eq(0)
    end

    it "labels a malformed version as unknown and an unlisted browser as other" do
      expect { post_events(events: [ "passkey_created" ], version: "<script>", browser: "netscape") }
        .to change { count_for("passkey_created", version: "unknown", browser: "other") }.by(1)
    end

    it "refuses a request with no events" do
      post_events(version: "4.0.1", browser: "chrome")

      expect(response).to have_http_status(:bad_request)
    end
  end
end
