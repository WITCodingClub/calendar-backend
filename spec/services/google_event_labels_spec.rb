# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleEventLabels do
  subject(:labels) { described_class.new(calendar_service, "synthetic-course-calendar") }

  let(:calendar_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar" }
  let(:calendar_service) do
    Google::Apis::CalendarV3::CalendarService.new.tap do |service|
      service.authorization = Signet::OAuth2::Client.new(access_token: "synthetic-user-token")
    end
  end

  def calendar_body(event_labels)
    { id: "synthetic-course-calendar", labelProperties: { eventLabels: event_labels } }.to_json
  end

  def stub_calendar(event_labels)
    stub_request(:get, calendar_url)
      .to_return(status: 200, body: calendar_body(event_labels), headers: { "Content-Type" => "application/json" })
  end

  def google_error(status)
    { status: status, body: { error: { code: status, message: "Synthetic error" } }.to_json,
      headers: { "Content-Type" => "application/json" } }
  end

  it "uses the label that the calendar already has for the color" do
    stub_calendar([ { id: "11111111-2222-3333-4444-555555555555", backgroundColor: "#1A2B3C" } ])

    expect(labels.label_id_for("#1a2b3c")).to eq("11111111-2222-3333-4444-555555555555")
    expect(labels).to be_available
  end

  it "adds a label for a new color and keeps the labels already on the calendar" do
    stub_calendar([ { id: "11111111-2222-3333-4444-555555555555", backgroundColor: "#1a2b3c", name: "Mine" } ])
    sent_labels = nil
    patch = stub_request(:patch, calendar_url).to_return do |request|
      sent_labels = JSON.parse(request.body).dig("labelProperties", "eventLabels")
      { status: 200, body: calendar_body(sent_labels), headers: { "Content-Type" => "application/json" } }
    end

    label_id = labels.label_id_for("#abcdef")

    expect(patch).to have_been_requested.once
    expect(sent_labels.first).to eq("id" => "11111111-2222-3333-4444-555555555555", "backgroundColor" => "#1a2b3c", "name" => "Mine")
    expect(sent_labels.last).to eq("id" => label_id, "backgroundColor" => "#abcdef")
  end

  it "reads the calendar once and adds each label once" do
    get = stub_calendar([])
    patch = stub_request(:patch, calendar_url).to_return do |request|
      { status: 200, body: request.body, headers: { "Content-Type" => "application/json" } }
    end

    first = labels.label_id_for("#abcdef")

    expect(labels.label_id_for("#abcdef")).to eq(first)
    expect(get).to have_been_requested.once
    expect(patch).to have_been_requested.once
  end

  it "is unavailable when Google does not return the calendar" do
    stub_request(:get, calendar_url).to_return(google_error(403))

    expect(labels.label_id_for("#abcdef")).to be_nil
    expect(labels).not_to be_available
  end

  it "is unavailable when Google does not keep the new label" do
    stub_calendar([])
    stub_request(:patch, calendar_url)
      .to_return(status: 200, body: calendar_body([]), headers: { "Content-Type" => "application/json" })

    expect(labels.label_id_for("#abcdef")).to be_nil
    expect(labels).not_to be_available
  end

  it "does not add a label when the calendar is full" do
    full = Array.new(described_class::MAX_LABELS) do |index|
      { id: SecureRandom.uuid, backgroundColor: format("#%06x", index) }
    end
    stub_calendar(full)

    expect(labels.label_id_for("#abcdef")).to be_nil
    expect(labels).to be_available
    expect(a_request(:patch, calendar_url)).not_to have_been_made
  end
end
