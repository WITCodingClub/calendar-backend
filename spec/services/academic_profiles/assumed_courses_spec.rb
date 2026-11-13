# frozen_string_literal: true

require "rails_helper"

# Issue #996: the courses that next term courses counts as passed.
RSpec.describe AcademicProfiles::AssumedCourses do
  describe ".parse" do
    it "reads codes separated by commas, with or without spaces, each one time" do
      expect(described_class.parse("COMP3350, math 2300,,COMP 3350")).to eq([ [ "COMP", 3350 ], [ "MATH", 2300 ] ])
    end

    it "reads a list of strings, and nothing from nil or an empty string" do
      expect(described_class.parse([ "COMP3350", "MATH2300,PHIL2100" ])).to eq([ [ "COMP", 3350 ], [ "MATH", 2300 ], [ "PHIL", 2100 ] ])
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse("")).to eq([])
    end

    it "raises for a value that is not a course code, a value of the wrong type, or too many codes" do
      expect { described_class.parse("COMP3350,Algorithms") }.to raise_error(described_class::InvalidCodesError, /course codes/)
      expect { described_class.parse({ "a" => "COMP3350" }) }.to raise_error(described_class::InvalidCodesError)
      expect { described_class.parse([ 3350 ]) }.to raise_error(described_class::InvalidCodesError)
      codes = (1000..1050).map { |number| "COMP#{number}" }.join(",")
      expect { described_class.parse(codes) }.to raise_error(described_class::InvalidCodesError, /at most 50/)
    end
  end
end
