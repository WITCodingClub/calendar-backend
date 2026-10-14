# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListSubjects do
  let(:user) { create(:user) }

  it "lists subjects with their codes and section counts" do
    term = create(:term)
    create_list(:course, 2, term: term, subject: "Computer Science (COMP)")
    create(:course, subject: "Mathematics (MATH)")

    result = described_class.call(server_context: { user: user }, term_uid: term.uid)

    expect(result.structured_content).to eq(
      term_uid: term.uid,
      subjects: [ { subject: "Computer Science (COMP)", code: "COMP", section_count: 2 } ]
    )
  end
end
