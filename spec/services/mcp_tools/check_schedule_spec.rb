# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::CheckSchedule do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "checks the CRNs in the term" do
    create(:course, term: term, crn: 20397)

    result = call(term_uid: term.uid, crns: [ 20397, 1 ])

    expect(result.error?).to be(false)
    expect(result.structured_content[:not_found]).to eq([ 1 ])
  end

  it "uses the current term when no term is given" do
    create(:course, term: term, crn: 20397)
    allow(Term).to receive(:current).and_return(term)

    expect(call(crns: [ 20397 ]).structured_content[:term][:uid]).to eq(term.uid)
  end

  it "queues a Banner refresh of the sections with old data only" do
    old_section = create(:course, term: term, crn: 20397, banner_synced_at: 37.hours.ago)
    create(:course, term: term, crn: 20398, banner_synced_at: 12.hours.ago)

    expect { call(term_uid: term.uid, crns: [ 20397, 20398 ]) }
      .to have_enqueued_job(Catalog::SectionRefreshJob).with([ old_section.id ])
  end

  it "returns a tool error for an empty list" do
    expect(call(term_uid: term.uid, crns: []).error?).to be(true)
  end

  it "is read-only" do
    expect(described_class.annotations.read_only_hint).to be(true)
  end
end
