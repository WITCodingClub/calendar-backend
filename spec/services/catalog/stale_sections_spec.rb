# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::StaleSections do
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  let(:term) { create(:term, uid: 202710, year: 2027, season: :fall, start_date: 1.month.ago, end_date: 2.months.from_now) }

  before { allow(Term).to receive(:synced_uids).and_return([ term.uid ]) }

  describe ".refresh" do
    it "queues the sections of a synced term that the nightly sync missed" do
      stale = create(:course, term: term, banner_synced_at: (described_class::FRESH_FOR + 1.hour).ago)
      create(:course, term: term, banner_synced_at: 1.hour.ago)

      expect { described_class.refresh(term.uid, Course.pluck(:crn)) }
        .to have_enqueued_job(Catalog::SectionRefreshJob).with([ stale.id ])
    end

    it "leaves out a term that the nightly sync does not read" do
      allow(Term).to receive(:synced_uids).and_return([])
      section = create(:course, term: term, banner_synced_at: nil)

      expect(described_class.refresh(term.uid, [ section.crn ])).to eq([])
    end

    it "does not queue a section again while its key holds" do
      section = create(:course, term: term, banner_synced_at: nil)
      described_class.refresh(term.uid, [ section.crn ])

      expect { described_class.refresh(term.uid, [ section.crn ]) }.not_to have_enqueued_job(Catalog::SectionRefreshJob)
    end
  end

  describe ".queue" do
    it "removes the keys when the job cannot be queued, so the next call tries again" do
      allow(Catalog::SectionRefreshJob).to receive(:perform_later).and_raise(StandardError)

      expect { described_class.queue([ 1 ]) }.to raise_error(StandardError)
      expect(Rails.cache.exist?(described_class.cache_key(1))).to be(false)
    end
  end
end
