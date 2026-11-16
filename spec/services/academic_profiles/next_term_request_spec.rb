# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::NextTermRequest do
  include ActiveSupport::Testing::TimeHelpers

  def request(term: nil, assume: nil)
    described_class.new(term: term, assume: assume, assume_plans: false, include_candidates: true)
  end

  it "refuses a term that is not a Banner code or a label" do
    expect { request(term: "Winter 2027") }
      .to raise_error(described_class::InvalidTermError, /Banner term code or a label/)
  end

  it "refuses an assume value that is not course codes" do
    expect { request(assume: "not a code") }.to raise_error(AcademicProfiles::PlanningError, /course codes/)
  end

  context "with a student in a program" do
    let(:user) { create(:user) }

    before do
      catalog_year = create(:catalog_year, :imported, start_year: 2025)
      major = create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.")
      create(:requirement_set, degree_program: major, catalog_year: catalog_year)
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)
      create(:term, uid: 202710, year: 2026, season: :fall, start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 20))
    end

    it "gives the courses of the parsed term, with the assumed courses" do
      result = request(term: "Spring 2027", assume: "COMP3350, math 2300").call(user)

      expect(result[:term]).to eq(uid: 202720, name: "Spring 2027")
      expect(result[:assumed][:courses]).to eq([ "COMP 3350", "MATH 2300" ])
    end

    it "uses the term after the current term for a blank term" do
      travel_to Time.zone.local(2026, 11, 6) do
        expect(request(term: "").call(user)[:term]).to eq(uid: 202720, name: "Spring 2027")
      end
    end
  end
end
