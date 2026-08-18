# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionQuery do
  include_context "catalog fixtures"

  subject(:query) { described_class.new }

  def crns_for(**filters)
    query.call(**filters).map(&:crn)
  end

  describe "#call with no filters" do
    it "returns every active section, ordered by subject, number, then section" do
      expect(crns_for).to eq([ 10_001, 10_002, 10_003, 20_001 ])
    end

    it "excludes cancelled sections" do
      expect(crns_for).not_to include(10_999)
    end
  end

  describe "include_cancelled" do
    it "adds cancelled sections when truthy" do
      expect(crns_for(include_cancelled: true)).to include(10_999)
    end

    it "keeps them out for the string \"false\"" do
      expect(crns_for(include_cancelled: "false")).not_to include(10_999)
    end
  end

  describe "term_uid" do
    it "keeps only sections in that term" do
      expect(crns_for(term_uid: 202_710)).to eq([ 10_001, 10_002, 10_003 ])
    end

    it "accepts several terms" do
      expect(crns_for(term_uid: [ 202_710, 202_620 ]).size).to eq(4)
    end
  end

  describe "subject" do
    it "matches the short code students type" do
      expect(crns_for(subject: "COMP")).to eq([ 10_001, 10_002, 10_003 ])
    end

    it "matches the stored label" do
      expect(crns_for(subject: "Mathematics (MATH)")).to eq([ 20_001 ])
    end

    it "accepts several subjects" do
      expect(crns_for(subject: %w[COMP MATH]).size).to eq(4)
    end
  end

  describe "course_number and crns" do
    it "filters by course number" do
      expect(crns_for(course_number: 2000)).to eq([ 10_002, 10_003 ])
    end

    it "filters by an explicit CRN list" do
      expect(crns_for(crns: [ 10_001, 20_001 ])).to eq([ 10_001, 20_001 ])
    end
  end

  describe "q" do
    it "matches the title" do
      expect(crns_for(q: "Course 1000")).to eq([ 10_001 ])
    end

    it "matches the course number as text" do
      expect(crns_for(q: "1750")).to eq([ 20_001 ])
    end

    it "treats LIKE wildcards as literal characters" do
      expect(crns_for(q: "%")).to be_empty
    end
  end

  describe "schedule_types" do
    it "accepts the enum key" do
      expect(crns_for(schedule_types: "lecture").size).to eq(4)
    end

    it "accepts the Banner code" do
      expect(crns_for(schedule_types: "LEC").size).to eq(4)
    end

    it "raises for an unknown type" do
      expect { query.call(schedule_types: "NOPE") }
        .to raise_error(described_class::FilterError, /Unknown schedule_type/)
    end
  end

  describe "credit_hours" do
    it "filters by credit hours" do
      expect(crns_for(credit_hours: 4).size).to eq(4)
      expect(crns_for(credit_hours: 1)).to be_empty
    end
  end

  describe "instructor" do
    it "matches on last name, case-insensitively" do
      expect(crns_for(instructor: "byron")).to eq([ 10_001, 10_003 ])
    end

    it "returns one row per section even when a section has several faculty" do
      comp1000.faculties << grace
      expect(crns_for(instructor: "o")).to eq([ 10_001, 10_002, 10_003 ])
    end
  end

  describe "meets_on" do
    it "keeps sections meeting on any of the given days" do
      expect(crns_for(meets_on: "friday")).to eq([ 10_001, 10_003 ])
    end

    it "raises for an unknown day" do
      expect { query.call(meets_on: "funday") }
        .to raise_error(described_class::FilterError, /Unknown day/)
    end
  end

  describe "free_days" do
    it "drops sections that meet on any of the given days" do
      expect(crns_for(free_days: "friday")).to eq([ 10_002, 20_001 ])
    end

    it "combines with meets_on" do
      expect(crns_for(meets_on: "monday", free_days: "friday")).to eq([ 20_001 ])
    end
  end

  describe "begins_after" do
    it "drops sections with any meeting starting earlier" do
      expect(crns_for(begins_after: "10:00")).to eq([ 10_002, 10_003, 20_001 ])
    end

    it "is inclusive of a meeting starting exactly at the boundary" do
      expect(crns_for(begins_after: "09:00")).to include(10_001)
    end

    it "accepts the HHMM form" do
      expect(crns_for(begins_after: "1000")).to eq(crns_for(begins_after: "10:00"))
    end
  end

  describe "ends_before" do
    it "drops sections with any meeting ending later" do
      expect(crns_for(ends_before: "14:30")).to eq([ 10_001, 10_002, 20_001 ])
    end

    it "is inclusive of a meeting ending exactly at the boundary" do
      expect(crns_for(ends_before: "14:15")).to include(10_002)
    end
  end

  describe "unknown filters" do
    it "raises rather than ignoring them silently" do
      expect { query.call(sort_by: "title") }
        .to raise_error(described_class::FilterError, /Unknown filter\(s\): sort_by/)
    end
  end

  describe ".parse_time" do
    it "converts HH:MM to the HHMM integer the columns store" do
      expect(described_class.parse_time("9:05")).to eq(905)
      expect(described_class.parse_time("13:45")).to eq(1345)
    end

    it "passes through the HHMM form" do
      expect(described_class.parse_time("1345")).to eq(1345)
      expect(described_class.parse_time(905)).to eq(905)
    end

    it "returns nil for a blank value" do
      expect(described_class.parse_time(nil)).to be_nil
      expect(described_class.parse_time("")).to be_nil
    end

    it "rejects impossible times" do
      expect { described_class.parse_time("25:00") }.to raise_error(described_class::FilterError)
      expect { described_class.parse_time("10:75") }.to raise_error(described_class::FilterError)
      expect { described_class.parse_time("noon") }.to raise_error(described_class::FilterError)
    end
  end

  describe ".with_associations" do
    it "eager-loads what the serializers read" do
      relation = described_class.with_associations(query.call(crns: 10_001))
      course   = relation.first
      expect(course.association(:faculties)).to be_loaded
      expect(course.association(:meeting_times)).to be_loaded
      expect(course.association(:term)).to be_loaded
    end
  end
end
