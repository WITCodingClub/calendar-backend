# frozen_string_literal: true

require "rails_helper"

# Drives TwentyFiveLive::Client through the HTTP boundary. WebMock stubs the
# 25Live web service, so the real fetch, retry, and sync code runs.
RSpec.describe TwentyFiveLive::Client, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  fixtures :buildings, :rooms

  let(:base_url) { TwentyFiveLive::Client::BASE_URL }

  let(:endpoints) do
    %w[
      organizations evcat evatrb resources spaces
      cabinets evcnrl evreq evtype orgcat orgcr orgat orgrtg orgtypes
      rscat resat rmcat rmat rmfeat rmconf
    ]
  end

  def stub_endpoint(name, body: "{}", status: 200)
    stub_request(:get, "#{base_url}#{name}.json").to_return(status: status, body: body)
  end

  def stub_fixture(name, file = name)
    stub_endpoint(name, body: file_fixture("twenty_five_live/#{file}.json").read)
  end

  # Stub every endpoint with an empty JSON object, then override per example.
  def stub_all_endpoints
    endpoints.each { |name| stub_endpoint(name) }
  end

  describe "#call!" do
    before do
      stub_all_endpoints
      stub_fixture("organizations")
      stub_fixture("evcat")
      stub_fixture("evatrb")
      stub_fixture("resources")
      stub_fixture("spaces")
    end

    it "returns true and syncs organizations, categories, attributes, resources, and spaces" do
      expect(described_class.new.call!).to be(true)

      org = TwentyFiveLive::Organization.find_by!(twenty_five_live_id: 101)
      expect(org).to have_attributes(code: "FCTORG", name: "Factory Robotics Club", organization_type_name: "Student Club")
      expect(TwentyFiveLive::Organization.find_by(twenty_five_live_id: 102)).to have_attributes(name: "Factory Chess Club")
      # Rows with a blank name or no id are skipped.
      expect(TwentyFiveLive::Organization.where(twenty_five_live_id: 103)).to be_empty
      expect(TwentyFiveLive::Organization.count).to eq(2)

      cat = TwentyFiveLive::EventCategory.find_by!(twenty_five_live_id: 1)
      expect(cat).to have_attributes(name: "Factory Lecture", sort_order: 3, defn_state: 1)
      expect(TwentyFiveLive::EventCategory.count).to eq(1)

      attr = TwentyFiveLive::EventCustomAttribute.find_by!(twenty_five_live_id: 5)
      expect(attr).to have_attributes(name: "Factory Attribute", attribute_type_name: "Text", sort_order: 2, defn_state: 1)
      expect(TwentyFiveLive::EventCustomAttribute.count).to eq(1)

      resource = TwentyFiveLive::Resource.find_by!(twenty_five_live_id: 7)
      expect(resource).to have_attributes(name: "Factory Projector", stock_level: 4)
      expect(TwentyFiveLive::Resource.count).to eq(1)

      expect(rooms(:wt_310).reload).to have_attributes(twenty_five_live_id: 9001, capacity: 36)
    end

    it "updates an existing record instead of adding a second one" do
      TwentyFiveLive::Organization.create!(twenty_five_live_id: 101, name: "Old Name")

      described_class.new.call!

      expect(TwentyFiveLive::Organization.where(twenty_five_live_id: 101).pluck(:name)).to eq([ "Factory Robotics Club" ])
    end

    it "reads r25: prefixed keys and a single object in place of a list" do
      stub_fixture("organizations", "organizations_prefixed")

      described_class.new.call!

      expect(TwentyFiveLive::Organization.find_by!(twenty_five_live_id: 201))
        .to have_attributes(code: "FCTP", name: "Factory Prefixed Org", organization_type_name: "Academic")
    end

    it "sends a basic auth header when credentials exist" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:TwentyFiveLive)
        .and_return({ username: "factory-user", password: "factory-pass" })

      described_class.new.call!

      expect(WebMock).to have_requested(:get, "#{base_url}organizations.json")
        .with(basic_auth: %w[factory-user factory-pass])
    end

    it "sends no auth header when credentials are missing" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:TwentyFiveLive).and_return(nil)

      described_class.new.call!

      expect(WebMock).to have_requested(:get, "#{base_url}organizations.json")
        .with { |req| req.headers["Authorization"].nil? }
    end

    it "requests every constant endpoint once and enqueues one drift mail" do
      expect { described_class.new.call! }
        .to have_enqueued_mail(TwentyFiveLiveMailer, :constant_drift_notification).once

      endpoints.each do |name|
        expect(WebMock).to have_requested(:get, "#{base_url}#{name}.json").once
      end
    end

    describe "constant drift" do
      let(:drifts) { [] }

      before do
        allow(TwentyFiveLiveMailer).to receive(:constant_drift_notification).and_wrap_original do |original, found|
          drifts.concat(found)
          original.call(found)
        end
      end

      it "reports an added, removed, and changed cabinet" do
        stub_fixture("cabinets")

        described_class.new.call!

        drift = drifts.find { |d| d[:entity] == "Cabinet" }
        expect(drift[:added]).to eq([ { id: 99, name: "Factory Cabinet" } ])
        expect(drift[:removed]).to eq([ { id: 15, name: "Events" } ])
        expect(drift[:changed]).to eq([
          { id: 10, name: "Renamed Courses",
            was: { name: "Courses", event_type_name: "Academics" },
            now: { name: "Renamed Courses", event_type_name: "Academics" } }
        ])
      end

      it "treats a null rate group in organization types as nil" do
        stub_fixture("orgtypes")

        described_class.new.call!

        drift = drifts.find { |d| d[:entity] == "OrganizationType" }
        expect(drift[:added]).to eq([ { id: 77, name: "Factory Type" } ])
        expect(drift[:changed]).to be_empty
      end

      # endpoint => [entity, list key, row key, row] in the 25Live response shape
      {
        "evcnrl"  => [ "EventRole", "roles", "role", { "role_id" => 9001, "role_name" => "Factory Role", "sort_order" => 1, "defn_state" => 1 } ],
        "evreq"   => [ "EventRequirement", "requirements", "requirement",
                       { "requirement_id" => 9001, "requirement_name" => "Factory Requirement", "stock_count" => 2, "allow_comment" => 1 } ],
        "evtype"  => [ "EventType", "event_types", "event_type", { "type_id" => 9001, "type_name" => "Factory Event Type" } ],
        "orgcat"  => [ "OrganizationCategory", "organization_categories", "category", { "category_id" => 9001, "category_name" => "Factory Org Category" } ],
        "orgcr"   => [ "OrganizationRole", "organization_roles", "role", { "role_id" => 9001, "role_name" => "Factory Org Role" } ],
        "orgat"   => [ "OrganizationCustomAttribute", "organization_custom_attributes", "attribute",
                       { "attribute_id" => 9001, "attribute_name" => "Factory Org Attribute", "attribute_type" => "T" } ],
        "orgrtg"  => [ "OrganizationRating", "organization_ratings", "rating", { "rating_id" => 9001, "rating_name" => "Factory Rating" } ],
        "rscat"   => [ "ResourceCategory", "resource_categories", "category", { "category_id" => 9001, "category_name" => "Factory Resource Category" } ],
        "resat"   => [ "ResourceCustomAttribute", "resource_custom_attributes", "attribute", { "attribute_id" => 9001, "attribute_name" => "Factory Resource Attribute" } ],
        "rmcat"   => [ "SpaceCategory", "space_categories", "category", { "category_id" => 9001, "category_name" => "Factory Space Category" } ],
        "rmat"    => [ "SpaceCustomAttribute", "space_custom_attributes", "attribute", { "attribute_id" => 9001, "attribute_name" => "Factory Space Attribute" } ],
        "rmfeat"  => [ "SpaceFeature", "space_features", "feature", { "feature_id" => 9001, "feature_name" => "Factory Feature" } ],
        "rmconf"  => [ "SpaceLayout", "space_layouts", "layout", { "layout_id" => 9001, "layout_name" => "Factory Layout" } ]
      }.each do |endpoint, (entity, list_key, row_key, row)|
        it "reports a new #{entity} row from #{endpoint}" do
          stub_endpoint(endpoint, body: { list_key => { row_key => [ row ] } }.to_json)

          described_class.new.call!

          drift = drifts.find { |d| d[:entity] == entity }
          expect(drift[:added].map { |a| a[:id] }).to eq([ 9001 ])
        end
      end

      it "skips a constant check that fails and logs a warning" do
        stub_endpoint("cabinets", status: 500)
        allow(Rails.logger).to receive(:warn)

        expect(described_class.new.call!).to be(true)

        expect(Rails.logger).to have_received(:warn).with(/Skipping Cabinet \(25Live API returned 500 for cabinets\)/)
        expect(drifts.map { |d| d[:entity] }).not_to include("Cabinet")
      end
    end
  end

  describe "#call!" do
    it "returns true when every request succeeds" do
      stub_all_endpoints

      expect(described_class.new.call!).to be(true)
    end

    [ 401, 403, 404, 500, 503 ].each do |status|
      it "raises a RequestError with status #{status}" do
        stub_endpoint("organizations", status: status)

        expect { described_class.new.call! }.to raise_error(TwentyFiveLive::Client::RequestError) { |error|
          expect(error.status).to eq(status)
          expect(error.message).to eq("25Live API returned #{status} for organizations")
        }
      end
    end

    it "raises for a body that is not JSON" do
      stub_endpoint("organizations", body: "<html>Service Unavailable</html>")

      expect { described_class.new.call! }.to raise_error(TwentyFiveLive::Client::RequestError) { |error|
        expect(error.message).to start_with("25Live API returned non-JSON for organizations")
        expect(error.status).to be_nil
      }
    end

    it "raises for an empty body as non-JSON" do
      stub_endpoint("organizations", body: "")

      expect { described_class.new.call! }.to raise_error(TwentyFiveLive::Client::RequestError)
    end

    it "raises for a JSON body of the wrong shape" do
      stub_endpoint("organizations", body: "[]")

      expect { described_class.new.call! }.to raise_error(TwentyFiveLive::Client::RequestError, /not a JSON object/)
    end

    it "does not retry an HTTP error status that is not a busy server" do
      stub_endpoint("organizations", status: 500)

      expect { described_class.new.call! }.to raise_error(TwentyFiveLive::Client::RequestError)

      expect(WebMock).to have_requested(:get, "#{base_url}organizations.json").once
    end
  end

  describe "network failures" do
    it "retries a timeout and then succeeds" do
      stub_all_endpoints
      stub_request(:get, "#{base_url}organizations.json")
        .to_timeout.then.to_timeout.then.to_return(status: 200, body: "{}")

      expect(described_class.new.call!).to be(true)
      expect(WebMock).to have_requested(:get, "#{base_url}organizations.json").times(3)
    end

    it "retries a busy server" do
      stub_all_endpoints
      stub_request(:get, "#{base_url}organizations.json").to_return({ status: 503 }, { status: 200, body: "{}" })

      expect(described_class.new.call!).to be(true)
    end

    it "raises after the last retry" do
      stub_request(:get, "#{base_url}organizations.json").to_timeout

      expect { described_class.new.call! }.to raise_error(Faraday::Error)
      expect(WebMock).to have_requested(:get, "#{base_url}organizations.json").times(HttpFetcher::RETRY_OPTIONS[:max] + 1)
    end

    [ Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED ].each do |error|
      it "retries #{error} and then raises" do
        stub_request(:get, "#{base_url}organizations.json").to_raise(error)

        expect { described_class.new.call! }.to raise_error(Faraday::Error)
        expect(WebMock).to have_requested(:get, "#{base_url}organizations.json").times(HttpFetcher::RETRY_OPTIONS[:max] + 1)
      end
    end
  end

  describe "RequestError" do
    it "keeps the status and the message" do
      error = TwentyFiveLive::Client::RequestError.new("boom", status: 502)

      expect(error).to have_attributes(message: "boom", status: 502)
    end
  end

  describe "spaces" do
    let(:wentworth_space) do
      {
        "space_id"      => 199,
        "space_name"    => "WT 310",
        "formal_name"   => "Wentworth Hall 310",
        "building_id"   => 22,
        "building_name" => "Wentworth Hall",
        "max_capacity"  => 36
      }
    end

    before { stub_all_endpoints }

    def sync_spaces(spaces)
      stub_endpoint("spaces", body: { "spaces" => { "space" => spaces } }.to_json)
      described_class.new.call!
    end

    it "associates 25Live IDs and formal names to room and building" do
      sync_spaces([ wentworth_space ])

      expect(rooms(:wt_310).reload).to have_attributes(twenty_five_live_id: 199, formal_name: "Wentworth Hall 310", capacity: 36)
      expect(buildings(:WT).reload).to have_attributes(twenty_five_live_id: 22, formal_name: "Wentworth Hall")
    end

    it "refreshes a capacity that changed, unlike the ID and the formal name" do
      rooms(:wt_310).update!(capacity: 30)

      sync_spaces([ wentworth_space ])

      expect(rooms(:wt_310).reload.capacity).to eq(36)
    end

    it "leaves capacity unknown when 25Live reports 0" do
      sync_spaces([ wentworth_space.merge("max_capacity" => 0) ])

      expect(rooms(:wt_310).reload.capacity).to be_nil
    end

    it "keeps a known capacity when 25Live reports 0" do
      rooms(:wt_310).update!(capacity: 30)

      sync_spaces([ wentworth_space.merge("max_capacity" => 0) ])

      expect(rooms(:wt_310).reload.capacity).to eq(30)
    end

    it "marks every building as checked, found in 25Live or not" do
      freeze_time do
        sync_spaces([ wentworth_space ])

        expect(buildings(:WT).reload.twenty_five_live_checked_at).to eq(Time.current)
        expect(buildings(:COMP).reload.twenty_five_live_checked_at).to eq(Time.current)
      end
    end

    it "skips a space whose abbreviation matches no building" do
      sync_spaces([ { "space_id" => 777, "space_name" => "NOPE 100", "building_id" => 99, "building_name" => "Unknown" } ])

      expect(rooms(:comp_100).reload.twenty_five_live_id).to be_nil
    end

    it "skips a space whose room number does not match" do
      sync_spaces([ { "space_id" => 888, "space_name" => "COMP 999", "building_id" => 55, "building_name" => "Computing Center" } ])

      expect(rooms(:comp_100).reload.twenty_five_live_id).to be_nil
    end

    it "skips a space_name with no room portion" do
      sync_spaces([ { "space_id" => 213, "space_name" => "AwayGame", "building_id" => 0, "building_name" => "" } ])

      expect(rooms(:wt_310).reload.twenty_five_live_id).to be_nil
    end

    it "does not overwrite an existing twenty_five_live_id on a room" do
      rooms(:wt_310).update!(twenty_five_live_id: 1, formal_name: "Original")

      sync_spaces([ wentworth_space ])

      expect(rooms(:wt_310).reload).to have_attributes(twenty_five_live_id: 1, formal_name: "Original")
    end

    it "skips TBD buildings" do
      buildings(:WT).update!(name: "To Be Determined", abbreviation: "TBD")

      sync_spaces([ { "space_id" => 999, "space_name" => "TBD 310", "building_id" => 22, "building_name" => "TBD" } ])

      expect(rooms(:wt_310).reload.twenty_five_live_id).to be_nil
    end
  end
end
