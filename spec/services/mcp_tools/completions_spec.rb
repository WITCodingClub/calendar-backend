# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::Completions do
  def complete(argument, value, prompt: "plan_term_schedule", context: nil)
    params = { ref: { type: "ref/prompt", name: prompt }, argument: { name: argument, value: value } }
    params[:context] = { arguments: context } if context
    described_class.call(params)[:completion]
  end

  describe "term" do
    let!(:past)    { create(:term, year: 2030, season: :fall) }
    let!(:current) { create(:term, year: 2031, season: :spring) }
    let!(:future)  { create(:term, year: 2031, season: :fall) }
    let!(:summer)  { create(:term, year: 2031, season: :summer) }

    before { allow(Term).to receive(:current).and_return(current) }

    it "gives the current and future terms first, then the past terms" do
      expect(complete("term", "")[:values]).to eq([ current, summer, future, past ].map { |term| term.uid.to_s })
    end

    it "matches the start of the uid or the name, ignoring case" do
      expect(complete("term", "2031")[:values]).to eq([ current, summer, future ].map { |term| term.uid.to_s })
      expect(complete("term", "FALL")[:values]).to eq([ future, past ].map { |term| term.uid.to_s })
      expect(complete("term", "fall 2030")[:values]).to eq([ past.uid.to_s ])
    end
  end

  describe "subject" do
    it "gives the subject codes that start with the value, in the term of the term argument" do
      term = create(:term)
      create(:course, term: term, subject: "Computer Science (COMP)")
      create(:course, term: term, subject: "Construction Management (CONM)")
      create(:course, term: term, subject: "Mathematics (MATH)")
      create(:course, subject: "Communication (COMM)")

      expect(complete("subject", "co", prompt: "find_class_for_free_time")[:values]).to eq(%w[COMM COMP CONM])
      expect(complete("subject", "co", prompt: "find_class_for_free_time", context: { term: term.uid.to_s })[:values])
        .to eq(%w[COMP CONM])
    end
  end

  describe "courses" do
    before do
      create(:catalog_course, subject_code: "COMP", course_number: 2350)
      create(:catalog_course, subject_code: "MATH", course_number: 1750)
      create(:catalog_course, subject_code: "MATH", course_number: 2300)
    end

    it "completes the last code in the list and keeps the codes before it" do
      expect(complete("courses", "comp 23")).to eq(values: [ "COMP 2350" ], hasMore: false)
      expect(complete("courses", "COMP 2350, math 17")[:values]).to eq([ "COMP 2350, MATH 1750" ])
      expect(complete("courses", "COMP 2350,ma")[:values]).to eq([ "COMP 2350, MATH 1750", "COMP 2350, MATH 2300" ])
    end

    it "gives at most 100 values and says there are more" do
      now = Time.current
      CatalogCourse.insert_all!(Array.new(101) { |i| { subject_code: "ZZZ", course_number: 1000 + i, created_at: now, updated_at: now } })

      result = complete("courses", "zzz")

      expect(result[:values].size).to eq(100)
      expect(result[:values].first).to eq("ZZZ 1000")
      expect(result[:hasMore]).to be(true)
    end
  end

  it "gives no values for an argument with no completions, an argument the prompt does not have, or a resource" do
    create(:catalog_course, subject_code: "COMP", course_number: 2350)

    expect(complete("preferences", "no")).to eq(values: [], hasMore: false)
    expect(complete("subject", "CO")).to eq(values: [], hasMore: false)
    expect(complete("courses", "CO", prompt: "check_my_schedule")).to eq(values: [], hasMore: false)
    expect(described_class.call({ ref: { type: "ref/resource", uri: "x" }, argument: { name: "courses", value: "CO" } }))
      .to eq(completion: { values: [], hasMore: false })
  end
end
