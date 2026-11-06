# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::TitleFormatter do
  def format(title)
    described_class.call(title)
  end

  it "capitalizes each word of a Banner title" do
    expect(format("SOFTWARE ENGINEERING")).to eq("Software Engineering")
  end

  it "writes roman numerals in capitals" do
    expect(format("CALCULUS II")).to eq("Calculus II")
    expect(format("PHYSICS IV")).to eq("Physics IV")
  end

  it "writes known acronyms in capitals" do
    expect(format("AGENTIC AI AND INTELLIGENT AGENTS")).to eq("Agentic AI And Intelligent Agents")
    expect(format("BME SENIOR DESIGN II")).to eq("BME Senior Design II")
    expect(format("GIS APPLICATIONS IN CIVIL ENGINEERING")).to eq("GIS Applications In Civil Engineering")
    expect(format("ARCHITECTURAL CADD")).to eq("Architectural CADD")
  end

  it "leaves an acronym inside a longer word alone" do
    expect(format("CAIRO GAIT STUDIES")).to eq("Cairo Gait Studies")
  end

  it "keeps an acronym in parentheses, dotted initials, and a number with letters" do
    expect(format("COMPUTER AIDED DESIGN (CAD)")).to eq("Computer Aided Design (CAD)")
    expect(format("U.S. HISTORY")).to eq("U.S. History")
    expect(format("3D MODELING")).to eq("3D Modeling")
  end

  it "joins a number to the single letter after it" do
    expect(format("STUDIO 2 A")).to eq("Studio 2A")
  end

  it "puts spaces around a hyphen between words" do
    expect(format("PRE-CALCULUS")).to eq("Pre - Calculus")
    expect(format("PRE-K-12 EDUCATION")).to eq("Pre - K - 12 Education")
  end

  it "joins a number and a letter that come before a hyphen" do
    expect(format("PART 2 B-SECTION")).to eq("Part 2B - Section")
  end

  it "decodes HTML entities, also when Banner encodes them twice" do
    expect(format("ETHICS &amp; SOCIETY")).to eq("Ethics & Society")
    expect(format("ETHICS &amp;amp; SOCIETY")).to eq("Ethics & Society")
  end

  it "returns nil for nil" do
    expect(format(nil)).to be_nil
  end

  # Course runs the formatter on every write, and the refresh task runs it on
  # stored titles, so a second pass must not change a formatted title.
  it "gives the same result when it runs on a formatted title" do
    [
      "AGENTIC AI AND INTELLIGENT AGENTS",
      "BME SENIOR DESIGN II",
      "COMPUTER AIDED DESIGN (CAD)",
      "U.S. HISTORY",
      "3D MODELING",
      "STUDIO 2 A",
      "PRE-CALCULUS",
      "ETHICS &amp; SOCIETY",
      "ETHICS &amp;amp; SOCIETY",
      "PRE-K-12 EDUCATION",
      "A-B-C-D",
      "PART 2 B-SECTION",
      "3 D-PRINTING"
    ].each do |raw|
      once = format(raw)
      expect(format(once)).to eq(once), "#{raw.inspect} changed on the second pass"
    end
  end

  it "fixes an acronym in a title that an older formatter stored" do
    expect(format("Introduction To Ai")).to eq("Introduction To AI")
  end
end
