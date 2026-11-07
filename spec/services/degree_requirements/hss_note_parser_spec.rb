# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::HssNoteParser do
  # CourseLeaf keeps the ENGL/HSS Note in the onclick of the "English
  # Sequence" link, as a JavaScript string with \x3c for "<".
  def bubble(html)
    escaped = html.gsub("<", "\\x3c").gsub(">", "\\x3e").gsub('"', "\\x22")
    %(<a href="#" onclick="lfjs.bubble(this,'#{escaped}',{width:500}); return false;" class="bubblelink code">English Sequence</a>)
  end

  def parse(body) = described_class.new(%(<html><body><article id="content">#{body}</article></body></html>)).call

  def categories(result) = result["categories"].map { |category| [ category["name"], category["subject_codes"], category["courses"] ] }

  let(:standard_note) do
    bubble("<p><strong>ENGL/HSS Note</strong></p><ul><li><p>At least one course in Humanities: CSAS, HSSI, HIST</p></li>" \
           "<li><p>At least one course in the Social Sciences: COMM, ECON</p></li></ul>" \
           "<p>A minimum of 20 credits total, including English, humanities, and social science credit, is required.</p>")
  end

  it "reads the credit total from the note in the bubble, with the humanities and social science categories" do
    result = parse(standard_note)

    expect(result["min_credits"]).to eq(20)
    expect(result["categories"].pluck("name")).to eq([ "Humanities", "Social Sciences" ])
    expect(result["categories"].first["subject_codes"]).to include("HIST", "PHIL")
  end

  it "adds an Ethics category, with the courses the page lists through a title with full stops" do
    result = parse("<p>Of the three listed electives BSCN students must include and Ethics course: " \
                   "PHIL4401 ENGINEERING ETHICS, PHIL4525 A.I. ETHICS or PHIL4600 DESIGNING THE GOOD LIFE</p>#{standard_note}")

    expect(categories(result).last).to eq([ "Ethics", [], %w[PHIL4401 PHIL4525 PHIL4600] ])
  end

  it "uses the known Ethics courses when the page names none" do
    result = parse("<p>ENGL/HSS Note: At least one of the HSS electives must be an Ethics course.</p>")

    expect(categories(result).last).to eq([ "Ethics", [], described_class::ETHICS_COURSES ])
  end

  it "reads directed courses, with the courses after or as choices for the same course" do
    result = parse("<p>Of the four humanities and social science electives, students must include the following:</p><table class=\"sc_courselist\">" \
                   "<tr><td>ECON4102</td><td>PRINCIPLES OF ECONOMICS</td><td>4</td></tr>" \
                   "<tr><td>or ECON4152</td><td>MACROECONOMICS</td></tr>" \
                   "<tr><td>PSYC4552</td><td>INDUSTRIAL ORGANIZATION PSYCHOLOGY</td><td>4</td></tr>" \
                   "<tr><td>MATH1750</td><td>A footnote course with no stop word before it</td></tr></table>")

    expect(categories(result).drop(2)).to eq([
      [ "Directed: ECON4102", [], %w[ECON4102 ECON4152] ],
      [ "Directed: PSYC4552", [], %w[PSYC4552] ]
    ])
  end

  it "reads a category of the major, with its courses, its subjects, or neither" do
    result = parse("<p>ENGL/HSS Note</p><ul><li>At least one elective in Art History (HUMN4243, HUMN4260);</li>" \
                   "<li>At least one elective in Psychology or Sociology.</li>" \
                   "<li>At least one elective in Design History;</li></ul>")

    expect(categories(result).drop(2)).to eq([
      [ "Art History", [], %w[HUMN4243 HUMN4260] ],
      [ "Psychology or Sociology", %w[PSYC SOCL], [] ],
      [ "Design History", [], [] ]
    ])
  end

  it "gives nil for a page with no HSS note, such as a minor" do
    expect(parse("<p>Select four courses from the following list.</p>")).to be_nil
  end

  it "takes the credit total from the page body over the footnote notes" do
    body = "<p>ENGL/HSS Note: A minimum of 24 credits total, including English, humanities, and social science credit.</p>"

    expect(parse(body + standard_note)["min_credits"]).to eq(24)
  end

  it "takes a footnote total only when every footnote gives the same one" do
    other = standard_note.sub("20 credits", "28 credits").sub("English Sequence", "HSS Elective")

    expect(parse(standard_note + other)["min_credits"]).to be_nil
  end
end
