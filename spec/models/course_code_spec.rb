# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCode do
  describe ".parse" do
    it "reads a code in any common spelling" do
      expect([ "COMP2350", "COMP 2350", "comp-2350" ].map { |text| described_class.parse(text) }).to all(eq([ "COMP", 2350 ]))
    end

    it "is nil for text that is not a code" do
      expect(described_class.parse("intro to programming")).to be_nil
    end
  end

  describe ".subject_of" do
    it "reads the code at the end of the label" do
      expect(described_class.subject_of("Computer Science (COMP)")).to eq("COMP")
      expect(described_class.subject_of("Graduate Internship (optional) (INTN)")).to eq("INTN")
    end

    it "gives a bare code in upper case" do
      expect(described_class.subject_of("comp")).to eq("COMP")
    end

    # "(optional)" is part of the name, not a code.
    it "keeps a subject with no code as it is" do
      expect(described_class.subject_of("Graduate Internship (optional)")).to eq("Graduate Internship (optional)")
    end
  end

  describe ".subject_sql" do
    it "reads the same code as subject_of" do
      sql = described_class.subject_sql("subject")

      expect(ActiveRecord::Base.connection.select_value("SELECT #{sql} FROM (SELECT 'Computer Science (COMP)' AS subject) t")).to eq("COMP")
    end
  end

  describe ".subject_condition" do
    it "matches the bare code and the label" do
      bare = create(:course, subject: "COMP")
      label = create(:course, subject: "Computer Science (COMP)")
      create(:course, subject: "Mathematics (MATH)")

      expect(Course.where(*described_class.subject_condition("courses.subject", [ "COMP" ]))).to contain_exactly(bare, label)
    end
  end
end
