# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ReimportAllTermsJob do
  include ActiveJob::TestHelper

  let(:counts) { { total: 3, processed: 3, failed: 0, failed_courses: [], created: 1, updated: 1, unchanged: 1 } }
  let!(:term) { create(:term, uid: 202720, year: 2027, season: :spring) }

  def plan(*uids)
    instance_double(Catalog::ReimportPlan,
                    call: Catalog::ReimportPlan::Result.new(term_uids: uids, missing_in_database: [ 202730 ], missing_in_banner: []))
  end

  it "builds the plan, imports the first term, and enqueues the rest" do
    allow(Catalog::ReimportPlan).to receive(:new).with(from: "202600", to: nil).and_return(plan(202720, 202710))
    allow(Catalog::ImportJob).to receive(:perform_now).with(202720).and_return(counts)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now(from: "202600") }
      .to have_enqueued_job(described_class).with(term_uids: [ 202710 ])

    expect(Rails.logger).to have_received(:info).with(/Term 202720: 1 added, 1 updated, 1 unchanged \(1 terms left\)/)
    expect(Rails.logger).to have_received(:warn).with(/not in the database, skipped: 202730/)
  end

  it "shows the term as importing on the admin pages while it runs" do
    allow(Catalog::ImportJob).to receive(:perform_now) do
      expect(term.reload.catalog_importing).to be(true)
      counts
    end

    described_class.perform_now(term_uids: [ 202720 ])
  end

  it "stops after the last term" do
    allow(Catalog::ImportJob).to receive(:perform_now).and_return(counts)

    expect { described_class.perform_now(term_uids: [ 202720 ]) }.not_to have_enqueued_job(described_class)
  end

  it "reports a failed term and goes on to the next one" do
    allow(Catalog::ImportJob).to receive(:perform_now).and_raise(RuntimeError, "Banner is down")

    reports = capture_error_reports do
      expect { described_class.perform_now(term_uids: [ 202720, 202710 ]) }
        .to have_enqueued_job(described_class).with(term_uids: [ 202710 ])
    end

    expect(reports.map { |report| report.error.class }).to eq([ RuntimeError ])
    expect(reports.first.context).to include(term_uid: 202720)
  end

  it "does nothing when the plan is empty" do
    allow(Catalog::ReimportPlan).to receive(:new).and_return(plan)
    allow(Catalog::ImportJob).to receive(:perform_now)

    described_class.perform_now

    expect(Catalog::ImportJob).not_to have_received(:perform_now)
  end

  it "uses a fixed concurrency group" do
    expect(described_class.concurrency_group).to eq("ReimportAllTermsJob")
  end
end
