# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#page_title" do
    it "returns the title the view set" do
      helper.content_for(:title, "Overview")

      expect(helper.page_title("Dashboard")).to eq("Overview")
    end

    it "returns the default when the view set no title" do
      expect(helper.page_title("Dashboard")).to eq("Dashboard")
    end

    it "returns nil when the view set no title and there is no default" do
      expect(helper.page_title).to be_nil
    end
  end

  describe "#browser_title" do
    it "adds the site name to the title the view set" do
      helper.content_for(:title, "Overview")

      expect(helper.browser_title("Dashboard")).to eq("Overview — WIT Calendar")
    end

    it "adds the site name to the default title" do
      expect(helper.browser_title("Dashboard")).to eq("Dashboard — WIT Calendar")
    end

    it "returns only the site name when there is no title and no default" do
      expect(helper.browser_title).to eq("WIT Calendar")
    end

    it "escapes the title one time only" do
      helper.content_for(:title, "Faculty & Staff")

      expect(helper.browser_title).to eq("Faculty &amp; Staff — WIT Calendar")
    end
  end

  describe "#structured_data_tag" do
    it "writes the data as JSON-LD" do
      html   = helper.structured_data_tag("@type": "TechArticle", headline: "Faculty & Staff")
      script = Nokogiri::HTML.fragment(html).at("script")

      expect(script["type"]).to eq("application/ld+json")
      expect(JSON.parse(script.text)).to eq("@type" => "TechArticle", "headline" => "Faculty & Staff")
    end

    it "does not let a value close the script tag" do
      html = helper.structured_data_tag(headline: "</script><script>alert(1)</script>")

      expect(html.scan("</script>").size).to eq(1)
    end
  end

  describe "#flash_style" do
    it "keeps errors on screen and announces them as alerts" do
      expect(helper.flash_style("alert")).to include(role: "alert", timeout: 0, icon: :exclamation_circle)
      expect(helper.flash_style(:error)).to include(role: "alert", timeout: 0)
    end

    it "keeps warnings on screen and announces them as alerts" do
      expect(helper.flash_style("warning")).to include(role: "alert", timeout: 0, icon: :exclamation)
    end

    it "closes notices after a delay and announces them as a status" do
      style = helper.flash_style(:notice)

      expect(style).to include(role: "status", icon: :check_circle)
      expect(style[:timeout]).to be_positive
    end

    it "gives each type its own color" do
      colors = %w[alert warning notice other].map { |type| helper.flash_style(type)[:css_class] }

      expect(colors.uniq.size).to eq(4)
    end

    it "shows an unknown type as information" do
      expect(helper.flash_style("other")).to include(role: "status", icon: :information)
    end
  end
end
