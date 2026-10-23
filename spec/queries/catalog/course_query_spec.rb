# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseQuery do
  describe "#codes_starting_with" do
    before do
      create(:catalog_course, subject_code: "COMP", course_number: 2350)
      create(:catalog_course, subject_code: "COMP", course_number: 2000)
      create(:catalog_course, subject_code: "COMP", course_number: 1000)
      create(:catalog_course, subject_code: "COOP", course_number: 3000)
      create(:catalog_course, subject_code: "MATH", course_number: 2300)
    end

    def codes(prefix, limit: 10) = described_class.new.codes_starting_with(prefix, limit: limit)

    it "matches the start of the subject code, ignoring case, in code order" do
      expect(codes("co")).to eq([ "COMP 1000", "COMP 2000", "COMP 2350", "COOP 3000" ])
    end

    it "matches the start of the number in one subject" do
      expect(codes("comp 23")).to eq([ "COMP 2350" ])
      expect(codes("COMP2")).to eq([ "COMP 2000", "COMP 2350" ])
      expect(codes("comp-1000")).to eq([ "COMP 1000" ])
    end

    it "matches the start of the number in every subject" do
      expect(codes("23")).to eq([ "COMP 2350", "MATH 2300" ])
    end

    it "gives the first courses for an empty value, and stops at the limit" do
      expect(codes("", limit: 2)).to eq([ "COMP 1000", "COMP 2000" ])
    end

    it "gives nothing for a value that is not part of a code" do
      expect(codes("intro to")).to eq([])
      expect(codes("CO%")).to eq([])
    end
  end
end
