# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::ProgramIndexParser do
  def parse(fixture, home_path)
    described_class.new(file_fixture("degree_requirements/#{fixture}").read, home_path: home_path)
  end

  context "with the tree index (2020-2021 and later)" do
    subject(:parser) { parse("programs_az_tree.html", "/previous-catalogs/2024-2025/") }

    it "lists each program once, and no department page" do
      expect(parser.entries.map(&:slug)).to eq(%w[
        widget-design-bs widget-design-bs-gears-concentration widget-design-ms widget-design-minor
        exploratory-wd gadget-cert sprocket-tech-aas widget-design-bs sprocket-studies-minor
      ])
    end

    it "keeps the site path of each program" do
      expect(parser.entries.first.path).to eq("/previous-catalogs/2024-2025/widgetry/widget-design/widget-design-bs/")
    end

    it "reads the kind and level from the name" do
      kinds = parser.entries.to_h { |entry| [ entry.path.split("/")[-1], [ entry.kind, entry.level ] ] }

      expect(kinds).to include(
        "widget-design-bs" => %w[bachelor undergraduate],
        "widget-design-bs-gears-concentration" => %w[concentration undergraduate],
        "widget-design-ms" => %w[master graduate],
        "widget-design-minor" => %w[minor undergraduate],
        "exploratory-wd" => %w[exploratory undergraduate],
        "gadget-cert" => %w[certificate graduate],
        "sprocket-tech-aas" => %w[associate undergraduate]
      )
    end

    it "names the major of a concentration" do
      concentration = parser.entries.find { |entry| entry.kind == "concentration" }

      expect(concentration.parent_name).to eq("Widget Design, B.S.")
    end

    it "leaves out a link with no program kind, and lists it" do
      expect(parser.entries.map(&:name)).not_to include("Gadget Guide")
      expect(parser.unclassified).to eq([ "Gadget Guide" ])
    end

    it "skips PDFs and the alphabetic listing tab" do
      expect(parser.entries.map(&:path)).to all(end_with("/"))
      expect(parser.entries.map(&:name)).not_to include("Should Not Appear, B.S.")
    end
  end

  context "with the flat A-Z index of 2019-2020" do
    subject(:parser) { parse("programs_az_flat.html", "/previous-catalogs/2019-2020/") }

    it "lists every link as a program" do
      expect(parser.entries.map { |entry| [ entry.slug, entry.kind ] }).to eq([
        %w[applied-gizmos-bs bachelor], %w[applied-gizmos-masters master], %w[widget-studies-minor minor]
      ])
      expect(parser.unclassified).to eq([ "Wobble Basics" ])
    end
  end

  context "with the current site" do
    it "reads paths that start at the site root" do
      html = <<~HTML
        <div id="textcontainer"><ul><li><a href="/widgetry/widget-design/widget-design-bs/">Widget Design, B.S.</a></li>
        <li><a href="/programs-az/accelerated-programs/">Accelerated Programs</a></li></ul></div>
      HTML

      entries = described_class.new(html, home_path: "/").entries

      expect(entries.map(&:path)).to eq([ "/widgetry/widget-design/widget-design-bs/" ])
    end

    it "turns an underscore in the path into a hyphen in the slug, and keeps the path" do
      html = %(<div id="textcontainer"><ul><li><a href="/widgetry/widget-design/widget-design-bs-gears_cogs/">) +
             %(Widget Design Bachelor of Science - Gears Concentration</a></li></ul></div>)

      entry = described_class.new(html, home_path: "/").entries.first

      expect(entry).to have_attributes(slug: "widget-design-bs-gears-cogs", path: "/widgetry/widget-design/widget-design-bs-gears_cogs/")
      program = DegreeProgram.new(slug: entry.slug).tap(&:validate)
      expect(program.errors[:slug]).to be_empty
    end
  end

  context "when one page has two names in the index" do
    it "takes the name with the most words of the slug" do
      html = <<~HTML
        <div id="textcontainer"><ul><li><a href="/maths/data-science/">Computer Science Minor</a></li>
        <li><a href="/maths/data-science/">Data Science Minor</a></li>
        <li><a href="/cs/computer-science-minor/">Computer Science Minor</a></li></ul></div>
      HTML

      entries = described_class.new(html, home_path: "/").entries

      expect(entries.map { |entry| [ entry.slug, entry.name ] }).to eq([
        [ "data-science", "Data Science Minor" ], [ "computer-science-minor", "Computer Science Minor" ]
      ])
    end
  end

  describe ".kind_for" do
    {
      "Exploratory Track in Engineering" => "exploratory",
      "Engineering B.S. - Advanced Manufacturing Track" => "concentration",
      "Construction Management Bachelor of Science - Infrastructure Concentration" => "concentration",
      "Data Analytics Certificate (graduate)" => "certificate",
      "Performing Arts Minor (COF Only)" => "minor",
      "Building Construction Management Associate Degree" => "associate",
      "Engineering Technology, A.A.S." => "associate",
      "Architecture, M. Arch." => "master",
      "Civil Engineering, M.Eng." => "master",
      "Architecture Masters Degree" => "master",
      "Applied Sciences, B.S" => "bachelor",
      "Computer Science Bachelor of Science" => "bachelor",
      "Non-Credit Workshops" => nil
    }.each do |name, kind|
      it "reads #{name.inspect} as #{kind.inspect}" do
        expect(described_class.kind_for(name)).to eq(kind)
      end
    end
  end
end
