# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionLinksSyncJob do
  it "syncs the links of the term" do
    term = create(:term)
    allow(Catalog::SectionLinksSync).to receive(:for_term).and_return(synced: 2, failed: 0)

    described_class.perform_now(term.uid)

    expect(Catalog::SectionLinksSync).to have_received(:for_term).with(term)
  end

  it "does nothing for an unknown term" do
    allow(Catalog::SectionLinksSync).to receive(:for_term)

    described_class.perform_now(1)

    expect(Catalog::SectionLinksSync).not_to have_received(:for_term)
  end

  it "runs one term at a time under a fixed group" do
    expect(described_class.concurrency_group).to eq("Catalog::SectionLinksSyncJob")
    expect(described_class.concurrency_limit).to eq(1)
  end
end
