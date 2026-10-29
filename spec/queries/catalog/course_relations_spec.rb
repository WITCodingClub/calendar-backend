# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseRelations do
  let(:term)   { create(:term) }
  let(:course) { create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2650) }

  describe "#prerequisites, #corequisites, and #unlocks" do
    it "reads them from the catalog course" do
      tree = { "type" => "course", "subject_code" => "COMP", "course_number" => 2000 }
      catalog = create(:catalog_course, subject_code: "COMP", course_number: 2650, prerequisites: tree,
                                        corequisites: [ { "subject_code" => "MATH", "course_number" => 2300 } ])
      later = create(:catalog_course)
      create(:course_prerequisite, catalog_course: later, required_catalog_course: catalog)

      relations = described_class.new(course)

      expect(relations.prerequisites).to eq(tree)
      expect(relations.corequisites).to eq([ { "subject_code" => "MATH", "course_number" => 2300 } ])
      expect(relations.unlocks).to eq([ later ])
    end

    it "gives empty values when the course has no catalog row" do
      relations = described_class.new(course)

      expect([ relations.prerequisites, relations.corequisites, relations.unlocks ]).to eq([ nil, [], [] ])
    end
  end

  describe "#mutual_exclusions" do
    it "reads them from the catalog course, and section_for finds their sections" do
      create(:catalog_course, subject_code: course.prefix, course_number: course.course_number,
                              mutual_exclusions: [ { "subject_code" => "ARCH", "course_number" => 6100 } ])
      excluded = create(:course, term: course.term, subject: "Architecture (ARCH)", course_number: 6100)
      relations = described_class.new(course)

      expect(relations.mutual_exclusions).to eq([ { "subject_code" => "ARCH", "course_number" => 6100 } ])
      expect(relations.section_for("ARCH", 6100)).to eq(excluded)
    end

    it "is empty when the course has no catalog row" do
      expect(described_class.new(course).mutual_exclusions).to eq([])
    end
  end

  describe "#cross_listed_sections" do
    it "gives the other active sections in the group, in the same term" do
      section = create(:course, :cross_listed, term: course.term)
      partner = create(:course, :cross_listed, term: course.term)
      create(:course, :cross_listed)

      expect(described_class.new(section).cross_listed_sections).to eq([ partner ])
    end

    it "is empty for a section that is not cross-listed" do
      expect(described_class.new(course).cross_listed_sections).to eq([])
    end
  end

  describe "#section_for" do
    it "prefers a section in the same term over a newer term" do
      tree = { "type" => "course", "subject_code" => "COMP", "course_number" => 2000 }
      create(:catalog_course, subject_code: "COMP", course_number: 2650, prerequisites: tree)
      newer_term = create(:term, year: term.year + 1)
      create(:course, term: newer_term, subject: "Computer Science (COMP)", course_number: 2000)
      same_term = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)

      expect(described_class.new(course).section_for("COMP", 2000)).to eq(same_term)
    end

    it "returns nil for a course with no section" do
      tree = { "type" => "course", "subject_code" => "COMP", "course_number" => 128 }
      create(:catalog_course, subject_code: "COMP", course_number: 2650, prerequisites: tree)

      expect(described_class.new(course).section_for("COMP", 128)).to be_nil
    end
  end

  describe "#linked_options" do
    it "gives Banner's partner sections" do
      course.update!(links_fetched_at: Time.current)
      link = create(:section_link, course: course)

      expect(described_class.new(course).linked_options).to eq([ [ link.linked_course ] ])
    end
  end
end
