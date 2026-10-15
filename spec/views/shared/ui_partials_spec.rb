# frozen_string_literal: true

require "rails_helper"

# Issue #699: the shared partials for patterns that the dashboard and the
# sign-in pages repeat.
RSpec.describe "shared UI partials", type: :view do
  def page(html) = Nokogiri::HTML::DocumentFragment.parse(html)

  describe "shared/page_header" do
    it "shows only the title when nothing else is given" do
      html = page(view.render("shared/page_header", title: "Settings"))

      expect(html.at_css("h1").text).to eq("Settings")
      expect(html.css("a, p")).to be_empty
      expect(html.css("div.flex-wrap > div")).to be_empty
    end

    it "shows the back link, the description, and the actions" do
      html = page(view.render("shared/page_header", title: "Requests", back: [ "Friends", "/dashboard/friends" ], description: "Pending requests.") { "<a href=\"/x\">Act</a>".html_safe })

      back = html.at_css("a[href='/dashboard/friends']")
      expect(back.text.strip).to eq("Friends")
      expect(back.at_css("svg")["aria-hidden"]).to eq("true")
      expect(html.at_css("p").text).to eq("Pending requests.")
      expect(html.at_css("a[href='/x']").text).to eq("Act")
    end
  end

  describe "shared/section_card" do
    it "puts the title in an h2 and the block in the body" do
      html = page(view.render("shared/section_card", title: "Incoming", description: "From friends.", id: "incoming") { "Body" })

      section = html.at_css("section#incoming.m3-card")
      expect(section.at_css("h2").text).to eq("Incoming")
      expect(section.at_css("p").text).to eq("From friends.")
      expect(section.text).to include("Body")
    end

    it "leaves out the id and the description when none is given" do
      section = page(view.render("shared/section_card", title: "Outgoing") { "" }).at_css("section")

      expect(section["id"]).to be_nil
      expect(section.at_css("p")).to be_nil
    end
  end

  describe "shared/list_link_row" do
    it "links the title and the hint, with a chevron" do
      link = page(view.render("shared/list_link_row", path: "/dashboard/schedule", title: "My Schedule", hint: "View courses")).at_css("a")

      expect(link["href"]).to eq("/dashboard/schedule")
      expect(link.text.squish).to eq("My Schedule View courses")
      expect(link.at_css("path")["d"]).to eq(IconHelper::ICONS[:chevron_right])
    end

    it "shows no hint when none is given" do
      link = page(view.render("shared/list_link_row", path: "/x", title: "ICS calendar feed")).at_css("a")

      expect(link.css("span > span").size).to eq(1)
    end
  end

  describe "shared/empty_state" do
    it "draws the named icon from IconHelper" do
      html = page(view.render("shared/empty_state", message: "No account.", icon: :link))

      expect(html.at_css("path")["d"]).to eq(IconHelper::ICONS[:link])
    end

    it "shows the message, the hint, and the action" do
      html = page(view.render("shared/empty_state", message: "No friends yet.", hint: "Add one.", action: { label: "Add", url: "/add", external: true }))

      expect(html.css("p").map(&:text)).to eq([ "No friends yet.", "Add one." ])
      expect(html.at_css("a[href='/add']")["target"]).to eq("_blank")
    end

    it "shows only the icon and the message when nothing else is given" do
      html = page(view.render("shared/empty_state", message: "No groups yet."))

      expect(html.css("p").size).to eq(1)
      expect(html.css("a")).to be_empty
    end
  end

  describe "shared/status_card" do
    it "uses the error colors for an error" do
      html = page(view.render("shared/status_card", title: "Failed", icon_name: :x, tone: :error) { "Try again." })

      expect(html.at_css("span")["class"]).to include("bg-error-container")
      expect(html.at_css("h1").text).to eq("Failed")
      expect(html.text).to include("Try again.")
    end

    it "uses the primary colors by default" do
      html = page(view.render("shared/status_card", title: "Connected", icon_name: :check) { "" })

      expect(html.at_css("span")["class"]).to include("bg-primary-container")
    end
  end
end
