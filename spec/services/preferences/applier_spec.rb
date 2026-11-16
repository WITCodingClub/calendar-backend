# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Applier do
  let(:user) { create(:user) }
  let(:university_event) { create(:university_calendar_event, summary: "Fall Break") }
  let(:event_data) do
    { summary: "Fall Break", start_time: Time.zone.local(2026, 10, 12), end_time: Time.zone.local(2026, 10, 12, 23, 59, 59),
      all_day: true, university_calendar_event_id: university_event.id }
  end

  it "resolves the color to a hex color" do
    create(:calendar_preference, :uni_cal_global, user: user, color_id: 3)

    expect(described_class.new(user).apply(university_event, event_data)[:color_id]).to eq(Preferences::Colors::GRAPE)
  end

  it "renders the title template" do
    create(:calendar_preference, :uni_cal_global, user: user, title_template: "WIT: {{summary}}")

    expect(described_class.new(user).apply(university_event, event_data)[:summary]).to eq("WIT: Fall Break")
  end

  it "keeps an event without a record as it is" do
    expect(described_class.new(user).apply(nil, event_data)).to eq(event_data)
  end

  it "does not change the hash it was given" do
    described_class.new(user).apply(university_event, event_data)

    expect(event_data[:color_id]).to be_nil
  end
end
