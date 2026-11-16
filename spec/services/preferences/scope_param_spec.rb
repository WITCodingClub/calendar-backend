# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::ScopeParam do
  let(:user) { create(:user) }

  {
    "global"          => { scope: "global", event_type: nil },
    "uni_cal"         => { scope: "uni_cal_global", event_type: nil },
    "uni_cal:holiday" => { scope: "uni_cal_category", event_type: "holiday" },
    "lecture"         => { scope: "event_type", event_type: "lecture" }
  }.each do |param, attributes|
    it "finds the #{param} level and names it back" do
      preference = described_class.find_or_initialize(user, param)

      expect(preference).to have_attributes(user: user, **attributes)
      expect(described_class.for(preference)).to eq(param)
    end
  end

  it "finds a saved row" do
    saved = user.calendar_preferences.create!(scope: :global, visibility: "private")

    expect(described_class.find_or_initialize(user, "global")).to eq(saved)
  end
end
