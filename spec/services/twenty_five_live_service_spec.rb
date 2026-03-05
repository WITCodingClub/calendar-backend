# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe TwentyFiveLiveService do
  let(:events_xml)  { Rails.root.join("spec/fixtures/files/twenty_five_live_events.xml").read }
  let(:events_url)  { "#{TwentyFiveLiveService::BASE_URL}events.xml" }

  let(:events_xml_pattern) { /webservices\.collegenet\.com.*events\.xml/ }

  def stub_events(body: events_xml, status: 200)
    stub_request(:get, /webservices\.collegenet\.com.*events\.xml/)
      .to_return(status: status, body: body, headers: { "Content-Type" => "text/xml" })
  end

  describe ".call with action: :sync_events" do
    subject(:service) { described_class.new(action: :sync_events) }

    before { stub_events }

    it "returns a result hash with created/updated/unchanged/errors keys" do
      result = service.call
      expect(result.keys).to match_array(%i[created updated unchanged errors])
    end

    context "event field parsing" do
      before { service.call }

      let(:event) { TwentyFiveLive::Event.find_by(event_id: 123_456) }

      it "parses event_id" do
        expect(event.event_id).to eq(123_456)
      end

      it "parses event_locator" do
        expect(event.event_locator).to eq("2024-TACOS")
      end

      it "parses event_name" do
        expect(event.event_name).to eq("Time Out and Tacos")
      end

      it "parses event_title" do
        expect(event.event_title).to eq("Taco Tuesday Event")
      end

      it "parses start_date" do
        expect(event.start_date).to eq(Date.parse("2026-03-10"))
      end

      it "parses end_date" do
        expect(event.end_date).to eq(Date.parse("2026-03-10"))
      end

      it "parses state" do
        expect(event.state).to eq(2)
      end

      it "parses state_name" do
        expect(event.state_name).to eq("Confirmed")
      end

      it "parses cabinet_id" do
        expect(event.cabinet_id).to eq(50)
      end

      it "parses cabinet_name" do
        expect(event.cabinet_name).to eq("Student Activities")
      end

      it "parses event_type_id" do
        expect(event.event_type_id).to eq(10)
      end

      it "parses event_type_name" do
        expect(event.event_type_name).to eq("Student Event")
      end

      it "decodes HTML entities in description" do
        expect(event.description).to eq("<p>Join us for tacos!</p>")
      end

      it "parses registration_url" do
        expect(event.registration_url).to eq("https://example.com/register")
      end

      it "parses public_website as true when custom_attribute id=32 is 'T'" do
        expect(event.public_website).to be(true)
      end

      it "sets last_synced_at" do
        expect(event.last_synced_at).to be_present
      end
    end

    context "minimal event (no title, no description)" do
      before { service.call }

      let(:event) { TwentyFiveLive::Event.find_by(event_id: 999) }

      it "creates the event" do
        expect(event).to be_present
      end

      it "sets event_title to nil" do
        expect(event.event_title).to be_nil
      end

      it "sets description to nil" do
        expect(event.description).to be_nil
      end

      it "sets public_website to false when custom_attribute id=32 is 'F'" do
        expect(event.public_website).to be(false)
      end
    end

    context "categories" do
      before { service.call }

      let(:event) { TwentyFiveLive::Event.find_by(event_id: 123_456) }

      it "creates 3 Category records" do
        expect(TwentyFiveLive::Category.count).to eq(3)
      end

      it "creates EventCategory joins for the event" do
        expect(event.categories.map(&:category_name)).to contain_exactly("Student Life", "Food", "Social")
      end
    end

    context "organizations" do
      before { service.call }

      let(:event) { TwentyFiveLive::Event.find_by(event_id: 123_456) }

      it "creates an Organization record" do
        expect(TwentyFiveLive::Organization.find_by(organization_id: 100)).to be_present
      end

      it "sets organization_name" do
        org = TwentyFiveLive::Organization.find_by(organization_id: 100)
        expect(org.organization_name).to eq("Student Government")
      end

      it "sets organization_title" do
        org = TwentyFiveLive::Organization.find_by(organization_id: 100)
        expect(org.organization_title).to eq("Student Government Association")
      end

      it "sets organization_type_id" do
        org = TwentyFiveLive::Organization.find_by(organization_id: 100)
        expect(org.organization_type_id).to eq(5)
      end

      it "sets organization_type_name" do
        org = TwentyFiveLive::Organization.find_by(organization_id: 100)
        expect(org.organization_type_name).to eq("Student Org")
      end

      it "sets the primary flag on the event_organization join" do
        event_org = TwentyFiveLive::EventOrganization.joins(:event)
                                                     .find_by(twenty_five_live_events: { event_id: 123_456 })
        expect(event_org.primary).to be(true)
      end

      it "associates organization to event through join" do
        expect(event.organizations.map(&:organization_name)).to contain_exactly("Student Government")
      end
    end

    context "reservations" do
      before { service.call }

      let(:event)       { TwentyFiveLive::Event.find_by(event_id: 123_456) }
      let(:reservation) { event.reservations.find_by(reservation_id: 789) }

      it "creates a Reservation record" do
        expect(reservation).to be_present
      end

      it "parses event_start_dt with timezone" do
        expect(reservation.event_start_dt).to eq(Time.parse("2026-03-10T12:00:00-05:00"))
      end

      it "parses event_end_dt with timezone" do
        expect(reservation.event_end_dt).to eq(Time.parse("2026-03-10T14:00:00-05:00"))
      end

      it "parses reservation_state" do
        expect(reservation.reservation_state).to eq(2)
      end

      it "parses expected_count from event level" do
        expect(reservation.expected_count).to eq(50)
      end
    end

    context "space reservations" do
      before { service.call }

      let(:event)       { TwentyFiveLive::Event.find_by(event_id: 123_456) }
      let(:reservation) { event.reservations.find_by(reservation_id: 789) }

      it "creates 2 Space records" do
        expect(reservation.spaces.count).to eq(2)
      end

      it "parses space formal_name" do
        formal_names = reservation.spaces.map(&:formal_name)
        expect(formal_names).to contain_exactly("Gordon Library Room 123", "Founders Hall Room 100")
      end

      it "parses space building_name" do
        space = TwentyFiveLive::Space.find_by(space_id: 200)
        expect(space.building_name).to eq("Gordon Library")
      end

      it "parses space max_capacity" do
        space = TwentyFiveLive::Space.find_by(space_id: 200)
        expect(space.max_capacity).to eq(100)
      end

      it "parses layout_name on space_reservation" do
        space_res = TwentyFiveLive::SpaceReservation.joins(:space)
                                                    .find_by(twenty_five_live_spaces: { space_id: 200 })
        expect(space_res.layout_name).to eq("Classroom")
      end

      it "parses selected_layout_capacity on space_reservation" do
        space_res = TwentyFiveLive::SpaceReservation.joins(:space)
                                                    .find_by(twenty_five_live_spaces: { space_id: 201 })
        expect(space_res.selected_layout_capacity).to eq(150)
      end
    end

    context "result counts" do
      it "reports created count on first sync" do
        result = service.call
        expect(result[:created]).to eq(2)
        expect(result[:updated]).to eq(0)
        expect(result[:unchanged]).to eq(0)
      end
    end

    context "upsert behavior" do
      it "updates existing records on second sync rather than creating duplicates" do
        service.call
        expect { service.call }.not_to change(TwentyFiveLive::Event, :count)
      end

      it "reports unchanged when nothing changed on second sync" do
        service.call
        result = service.call
        expect(result[:unchanged]).to eq(2)
        expect(result[:created]).to eq(0)
      end
    end
  end

  describe "pagination" do
    let(:page1_xml) { Rails.root.join("spec/fixtures/files/twenty_five_live_events_page1.xml").read }
    let(:page2_xml) { Rails.root.join("spec/fixtures/files/twenty_five_live_events_page2.xml").read }

    before do
      call_count = 0
      stub_request(:get, /webservices\.collegenet\.com.*events\.xml/).to_return do |_request|
        call_count += 1
        body = call_count == 1 ? page1_xml : page2_xml
        { status: 200, body: body, headers: { "Content-Type" => "text/xml" } }
      end
    end

    it "fetches all pages and creates events from each" do
      described_class.new(action: :sync_events).call
      expect(TwentyFiveLive::Event.pluck(:event_id)).to contain_exactly(111, 222)
    end
  end

  describe "error handling" do
    it "raises on empty response body" do
      stub_events(body: "")
      expect { described_class.new(action: :sync_events).call }.to raise_error("Empty events.xml body")
    end

    it "raises on non-200 HTTP status" do
      stub_events(status: 503, body: "Service Unavailable")
      expect { described_class.new(action: :sync_events).call }.to raise_error(/HTTP 503/)
    end
  end

  describe "unknown action" do
    it "raises ArgumentError" do
      expect { described_class.new(action: :bogus).call }.to raise_error(ArgumentError, /Unknown action/)
    end
  end
end
