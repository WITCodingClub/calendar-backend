# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseDetailsSyncJob do
  include ActiveSupport::Testing::TimeHelpers

  it "syncs the term" do
    term = create(:term)
    sync = instance_double(Catalog::CourseDetailsSync, call: Catalog::CourseDetailsSync::Result.new(fetched: 1, skipped: 0, failed: 0))
    allow(Catalog::CourseDetailsSync).to receive(:new).with(term).and_return(sync)

    freeze_time do
      described_class.perform_now(term.uid)

      expect(sync).to have_received(:call)
      # Catalog::Freshness reports this time in the MCP advisory.
      expect(term.reload.details_synced_at).to eq(Time.current)
    end
  end

  it "does nothing for an unknown term" do
    allow(Catalog::CourseDetailsSync).to receive(:new)

    described_class.perform_now(1)

    expect(Catalog::CourseDetailsSync).not_to have_received(:new)
  end

  it "runs one term at a time under a fixed group" do
    expect(described_class.concurrency_group).to eq("CatalogCourseDetailsSyncJob")
    expect(described_class.concurrency_limit).to eq(1)
  end
end
