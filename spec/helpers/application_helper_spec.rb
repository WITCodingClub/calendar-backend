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
end
