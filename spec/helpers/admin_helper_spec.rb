# frozen_string_literal: true

require "rails_helper"

# The shared admin partials (issue #655) render through these helpers.
RSpec.describe AdminHelper do
  def html(fragment)
    Nokogiri::HTML::DocumentFragment.parse(fragment)
  end

  describe "#admin_icon" do
    it "draws a decorative svg" do
      svg = html(helper.admin_icon(:users)).at_css("svg")

      expect(svg["aria-hidden"]).to eq("true")
      expect(svg.at_css("path")["d"]).to eq(AdminHelper::ICONS[:users])
    end

    it "raises for an unknown icon, so a typo fails a spec" do
      expect { helper.admin_icon(:nope) }.to raise_error(KeyError)
    end
  end

  describe "#admin_badge" do
    it "puts the text in a span with the tone's colors" do
      span = html(helper.admin_badge("Failed", :danger)).at_css("span")

      expect(span.text).to eq("Failed")
      expect(span["class"]).to include("bg-error-container")
    end

    it "escapes the text" do
      expect(helper.admin_badge("<b>x</b>")).to include("&lt;b&gt;")
    end
  end

  describe "#admin_table" do
    let(:rows) { [ Struct.new(:name, :count).new("Alpha", 3), Struct.new(:name, :count).new("Beta", nil) ] }

    def render_table(rows, **options)
      helper.admin_table(rows, **options) do |t|
        t.column("Name") { |row| helper.tag.strong(row.name) }
        t.column("Count", align: :right, &:count)
      end
    end

    it "renders a header cell for each column and a row for each record" do
      table = html(render_table(rows))

      expect(table.css("th").map(&:text)).to eq(%w[Name Count])
      expect(table.css("tbody tr").size).to eq(2)
      expect(table.css("tbody strong").map(&:text)).to eq(%w[Alpha Beta])
    end

    it "labels each cell for the stacked small-screen layout" do
      cells = html(render_table(rows)).css("tbody tr").first.css("td")

      expect(cells.pluck("data-label")).to eq(%w[Name Count])
      expect(cells.first["class"]).to include("admin-table-primary")
    end

    it "shows a value the block returns, and a dash for a blank one" do
      counts = html(render_table(rows)).css("tbody tr").map { |tr| tr.css("td").last.text.strip }

      expect(counts).to eq([ "3", "—" ])
    end

    it "shows the empty message when there are no rows" do
      expect(html(render_table([], empty: "No widgets yet.")).text).to include("No widgets yet.")
    end
  end

  describe "#admin_details" do
    it "renders a label and a value for each item" do
      list = html(helper.admin_details { |d| d.item("Email") { "a@wit.edu" } })

      expect(list.at_css("dt").text).to eq("Email")
      expect(list.at_css("dd").text.strip).to eq("a@wit.edu")
    end
  end

  describe "#admin_page_window" do
    it "keeps the first, the last, and the pages near the current one" do
      expect(helper.admin_page_window(10, 20)).to eq([ 1, nil, 8, 9, 10, 11, 12, nil, 20 ])
    end

    it "has no gaps for a short list" do
      expect(helper.admin_page_window(2, 4)).to eq([ 1, 2, 3, 4 ])
    end
  end

  describe "#admin_flash_style" do
    it "keeps an alert open until the admin closes it" do
      expect(helper.admin_flash_style("alert")).to include(tone: :danger, timeout: 0, role: "alert")
    end

    it "closes a notice after a while" do
      expect(helper.admin_flash_style(:notice)[:timeout]).to be_positive
    end
  end
end
