# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListTerms do
  let(:user) { create(:user) }

  it "lists the terms newest first with section counts and the current term" do
    older = create(:term, year: 2030)
    newer = create(:term, year: 2031)
    create(:course, term: newer)
    allow(Term).to receive(:current).and_return(newer)

    result = described_class.call(server_context: mcp_context(user))

    expect(result.error?).to be(false)
    expect(result.structured_content[:current_term_uid]).to eq(newer.uid)
    expect(result.structured_content).to have_key(:next_term_uid)
    expect(result.structured_content[:terms].pluck(:uid)).to eq([ newer.uid, older.uid ])
    expect(result.structured_content[:terms].first[:section_count]).to eq(1)
  end

  it "lists only the active terms when asked" do
    create(:term)
    allow(Term).to receive(:active).and_return(Term.none)

    expect(described_class.call(server_context: mcp_context(user), active: true).structured_content[:terms]).to be_empty
  end
end
