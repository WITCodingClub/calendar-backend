# frozen_string_literal: true

require "rails_helper"

# Issue #699: one set of icons for the dashboard, the sign-in pages, and admin.
RSpec.describe IconHelper do
  def html(fragment)
    Nokogiri::HTML::DocumentFragment.parse(fragment)
  end

  describe "#icon" do
    it "draws an outline icon that screen readers skip" do
      svg = html(helper.icon(:chevron_right, css_class: "w-4 h-4")).at_css("svg")

      expect(svg["aria-hidden"]).to eq("true")
      expect(svg["focusable"]).to eq("false")
      expect(svg["class"]).to eq("w-4 h-4")
      expect(svg["stroke"]).to eq("currentColor")
      expect(svg.at_css("path")["d"]).to eq(IconHelper::ICONS[:chevron_right])
    end

    it "sets the stroke width" do
      path = html(helper.icon("home", stroke_width: 2.5)).at_css("path")

      expect(path["stroke-width"]).to eq("2.5")
    end

    it "draws each path of an outline icon that has more than one" do
      paths = html(helper.icon(:cog)).css("path")

      expect(paths.pluck("d")).to eq(IconHelper::ICONS[:cog])
    end

    it "draws a filled icon with the brand colors" do
      svg = html(helper.icon(:google)).at_css("svg")

      expect(svg["fill"]).to eq("currentColor")
      expect(svg.css("path").pluck("fill")).to eq(%w[#4285F4 #34A853 #FBBC05 #EA4335])
    end

    it "lets a filled path with no color take the text color" do
      path = html(helper.icon(:passkey)).at_css("path")

      expect(path["fill"]).to be_nil
    end

    it "raises for an unknown icon, so a typo fails a spec" do
      expect { helper.icon(:nope) }.to raise_error(KeyError)
    end
  end

  describe "#logo_mark" do
    it "puts the calendar icon in a sized box" do
      span = html(helper.logo_mark(:large)).at_css("span")

      expect(span["class"]).to include("w-16 h-16 rounded-full", "bg-primary-container")
      expect(span["aria-hidden"]).to eq("true")
      expect(span.at_css("svg")["class"]).to include("w-8 h-8")
      expect(span.at_css("path")["d"]).to eq(IconHelper::ICONS[:calendar])
    end

    it "raises for an unknown size" do
      expect { helper.logo_mark(:huge) }.to raise_error(KeyError)
    end
  end
end
