# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::CatalogHelper, type: :helper do
  describe "#catalog_requisite" do
    let(:tree) do
      {
        "type" => "and",
        "operands" => [
          { "type" => "course", "code" => "MATH 1750", "linked" => true, "title" => "Calculus I" },
          {
            "type" => "or",
            "operands" => [
              { "type" => "course", "code" => "COMP 128", "linked" => false, "min_grade" => "C" },
              { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" }
            ]
          }
        ]
      }
    end

    it "links known courses and puts a nested group in parentheses" do
      html = Nokogiri::HTML.fragment(helper.catalog_requisite(tree))

      expect(html.text.squish).to eq("MATH 1750 and (COMP 128 (min C) or WIT Math Assessment 1500)")
      expect(html.css("a").map { |link| [ link.text, link["href"] ] }).to eq([ [ "MATH 1750", "/dashboard/courses/MATH1750" ] ])
    end
  end

  describe "#seats_line" do
    it "counts the open seats" do
      expect(helper.seats_line({ capacity: 30, available: 12 })).to eq("12 of 30 open")
    end

    it "is nil when Banner gave no counts" do
      expect(helper.seats_line({ capacity: nil, available: nil })).to be_nil
    end
  end

  describe "#rmp_summary" do
    it "summarizes the rating" do
      expect(helper.rmp_summary({ avg_rating: BigDecimal("4.26"), num_ratings: 1 })).to eq("4.3 / 5 from 1 rating")
    end

    it "is nil with no ratings" do
      expect(helper.rmp_summary(nil)).to be_nil
    end
  end

  describe "#event_time_range" do
    let(:zone) { Time.zone }

    it "shows one day for a one-day all-day event" do
      event = build(:university_calendar_event, all_day: true, start_time: zone.local(2026, 11, 11), end_time: zone.local(2026, 11, 12))

      expect(helper.event_time_range(event)).to eq("Wed, Nov 11")
    end

    it "shows the times of an event that ends on a later day" do
      event = build(:university_calendar_event, start_time: zone.local(2026, 11, 11, 18), end_time: zone.local(2026, 11, 12, 2))

      expect(helper.event_time_range(event)).to eq("Wed, Nov 11, 6:00 PM – Thu, Nov 12, 2:00 AM")
    end
  end

  describe "#event_category_label" do
    it "names a category" do
      expect(helper.event_category_label("study_day")).to eq("Study day")
      expect(helper.event_category_label(nil)).to eq("Other")
    end
  end
end
