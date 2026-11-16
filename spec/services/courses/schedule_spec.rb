# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::Schedule do
  include ActiveSupport::Testing::TimeHelpers

  describe ".week_start_for" do
    it "gives the Monday of the week of the date" do
      expect(described_class.week_start_for("2026-09-17")).to eq(Date.new(2026, 9, 14))
    end

    it "gives the Monday of this week for a value that is not a date" do
      travel_to Time.zone.local(2026, 9, 17, 12) do
        expect(described_class.week_start_for("soon")).to eq(Date.new(2026, 9, 14))
        expect(described_class.week_start_for(nil)).to eq(Date.new(2026, 9, 14))
      end
    end
  end

  describe ".build" do
    let(:user) { create(:user) }

    it "falls back to this week and month for bad values, with no term" do
      travel_to Time.zone.local(2026, 9, 17, 12) do
        schedule = described_class.build(user, week_start: "x", month: "y", view: "grid")

        expect(schedule).to have_attributes(selected_term: nil, courses: [], view_mode: "auto",
                                            week_start: Date.new(2026, 9, 14), month_date: Date.new(2026, 9, 1))
      end
    end

    it "lists the no-class days of the visible week and month" do
      create(:university_calendar_event, category: "holiday",
                                         start_time: Time.zone.local(2026, 9, 7), end_time: Time.zone.local(2026, 9, 7, 23, 59))

      schedule = described_class.build(user, week_start: "2026-09-28", month: "2026-09")

      expect(schedule.no_class_dates).to eq([ Date.new(2026, 9, 7) ])
    end
  end
end
