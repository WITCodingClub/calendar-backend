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

  # Banner writes "CO-OP" with no spaces and "STUDIO 01 - LAB" with spaces.
  it "keeps each hyphen as Banner sends it and capitalizes the word after it" do
    expect(format("INTRO TO CO-OP")).to eq("Intro To Co-Op")
    expect(format("PRE-K-12 EDUCATION")).to eq("Pre-K-12 Education")
    expect(format("STUDIO 01 - LAB")).to eq("Studio 01 - Lab")
  end

  it "capitalizes a word after a slash or an opening parenthesis" do
    expect(format("BASICS OF ORGANIC/BIOCHEM")).to eq("Basics Of Organic/Biochem")
    expect(format("STUDIO 07 (EMERGING TECH-BERLIN)")).to eq("Studio 07 (Emerging Tech-Berlin)")
  end

  it "writes degree program codes in capitals" do
    expect(format("INTRO TO CO-OP: BE/BME/CE/SSH")).to eq("Intro To Co-Op: Be/BME/CE/SSH")
    expect(format("ENGR LABORATORY - BSCE/BSEN")).to eq("Engr Laboratory - BSCE/BSEN")
    expect(format("PRE CO-OP WORK TERM(BCOT/BSCO)")).to eq("Pre Co-Op Work Term(BCOT/BSCO)")
  end

  it "turns an HTML line break into a dash" do
    expect(format("INTRODUCTION TO ENGINEERING DESIGN<br>BSCE/BSEN")).to eq("Introduction To Engineering Design - BSCE/BSEN")
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
      "3 D-PRINTING",
      "INTRO TO CO-OP: BE/BME/CE/SSH",
      "STUDIO 07 (AI-URBINO)",
      "INTRODUCTION TO ENGINEERING DESIGN<br>BSCE/BSEN"
    ].each do |raw|
      once = format(raw)
      expect(format(once)).to eq(once), "#{raw.inspect} changed on the second pass"
    end
  end

  it "fixes an acronym in a title that an older formatter stored" do
    expect(format("Introduction To Ai")).to eq("Introduction To AI")
  end
end
