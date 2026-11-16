# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Applier do
  let(:user) { create(:user) }
  let(:university_event) { create(:university_calendar_event, summary: "Fall Break") }
  let(:event) do
    CourseCalendars::Event.new(source: university_event, summary: "Fall Break", start_time: Time.zone.local(2026, 10, 12),
                               end_time: Time.zone.local(2026, 10, 12, 23, 59, 59), all_day: true)
  end

  it "resolves the color to a hex color" do
    create(:calendar_preference, :uni_cal_global, user: user, color_id: 3)

    expect(described_class.new(user).apply(event).color_id).to eq(Preferences::Colors::GRAPE)
  end

  it "renders the title template" do
    create(:calendar_preference, :uni_cal_global, user: user, title_template: "WIT: {{summary}}")

    expect(described_class.new(user).apply(event).summary).to eq("WIT: Fall Break")
  end

  it "strips the space a blank variable leaves in the location" do
    create(:calendar_preference, :uni_cal_global, user: user, location_template: "{{location}} ")

    expect(described_class.new(user).apply(event).location).to eq(university_event.location.to_s)
  end
end
