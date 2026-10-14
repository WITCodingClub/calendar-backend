# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionLinks do
  let(:term) { create(:term) }
  let(:lecture_a1) { create(:course, term: term, course_number: 4960, is_section_linked: true, link_identifier: "A1") }
  let(:lab_b1)     { create(:course, term: term, course_number: 4960, is_section_linked: true, link_identifier: "B1") }
  let(:lecture_a2) { create(:course, term: term, course_number: 4960, is_section_linked: true, link_identifier: "A2") }

  it "guesses from the link identifiers before Banner's pairs are fetched" do
    lab_b1

    json = described_class.new(lecture_a1).as_json

    expect(json).to include(required: true, identifier: "A1", source: "link_identifier", crns: [ lab_b1.crn ],
                            pub_ids: [ lab_b1.public_id ], options: [ [ lab_b1.crn ] ])
  end

  it "uses Banner's pairs once they are fetched, even when the identifiers disagree" do
    lab_b1
    create(:section_link, course: lecture_a2, linked_course: lab_b1)
    lecture_a2.update!(links_fetched_at: Time.current)

    json = described_class.new(lecture_a2).as_json

    expect(json).to include(required: true, source: "banner", crns: [ lab_b1.crn ], options: [ [ lab_b1.crn ] ])
  end

  it "keeps Banner's option groups" do
    lab_b2 = create(:course, term: term, course_number: 4960)
    rec    = create(:course, term: term, course_number: 4960)
    create(:section_link, course: lecture_a1, linked_course: lab_b1, option_group: 0)
    create(:section_link, course: lecture_a1, linked_course: lab_b2, option_group: 1)
    create(:section_link, course: lecture_a1, linked_course: rec, option_group: 1)
    lecture_a1.update!(links_fetched_at: Time.current)

    expect(described_class.new(lecture_a1).as_json[:options])
      .to eq([ [ lab_b1.crn ], [ lab_b2.crn, rec.crn ].sort ])
  end

  it "says a section with no Banner partners stands alone" do
    lecture_a1.update!(links_fetched_at: Time.current)

    expect(described_class.new(lecture_a1).as_json).to include(required: false, source: "banner", crns: [], options: [])
  end

  it "gives no partners for an unlinked section" do
    course = create(:course, term: term)

    expect(described_class.new(course).as_json).to include(required: false, crns: [], options: [])
  end
end
