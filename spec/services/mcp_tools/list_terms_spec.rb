# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListTerms do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it "lists the terms newest first with section counts and the current term" do
    older = create(:term, year: 2030)
    newer = create(:term, year: 2031)
    create(:course, term: newer)

    result = travel_to(Time.zone.local(newer.year, 10, 1)) { described_class.call(server_context: mcp_context(user)) }

    expect(result.error?).to be(false)
    expect(result.structured_content[:current_term_uid]).to eq(newer.uid)
    expect(result.structured_content).to have_key(:next_term_uid)
    expect(result.structured_content[:terms].pluck(:uid)).to eq([ newer.uid, older.uid ])
    expect(result.structured_content[:terms].first[:section_count]).to eq(1)
  end

  it "lists only the active terms when asked" do
    active = create(:term, year: 2030, start_date: Date.new(2030, 9, 3), end_date: Date.new(2030, 12, 20))
    create(:term, year: 2029, start_date: Date.new(2029, 9, 4), end_date: Date.new(2029, 12, 21))

    terms = travel_to(Time.zone.local(2030, 10, 1)) do
      described_class.call(server_context: mcp_context(user), active: true).structured_content[:terms]
    end

    expect(terms.pluck(:uid)).to eq([ active.uid ])
  end
end
