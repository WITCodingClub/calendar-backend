# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SubjectQuery do
  it "counts active sections per subject, by subject" do
    term = create(:term)
    create_list(:course, 2, term: term, subject: "Mathematics (MATH)")
    create(:course, term: term, subject: "COMP")
    create(:course, term: term, subject: "COMP", status: :cancelled)
    create(:course, subject: "Biology (BIOL)")

    expect(described_class.new.call(term_uid: term.uid)).to eq([
      { subject: "COMP", code: "COMP", section_count: 1 },
      { subject: "Mathematics (MATH)", code: "MATH", section_count: 2 }
    ])
  end

  describe "#codes" do
    it "gives each subject code with active sections one time, sorted" do
      term = create(:term)
      create_list(:course, 2, term: term, subject: "Mathematics (MATH)")
      create(:course, term: term, subject: "COMP")
      create(:course, term: term, subject: "Physics (PHYS)", status: :cancelled)
      create(:course, subject: "Biology (BIOL)")

      expect(described_class.new.codes(term_uids: [ term.uid ])).to eq(%w[COMP MATH])
      expect(described_class.new.codes).to eq(%w[BIOL COMP MATH])
    end
  end
end
