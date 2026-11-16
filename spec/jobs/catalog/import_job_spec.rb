# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ImportJob do
  include ActiveJob::TestHelper

  let(:term) { create(:term) }

  it "imports the courses, then enqueues the course details sync" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).with(term: term.uid).and_return([ { crn: 1 } ])
    counts = { total: 1, processed: 1, failed: 0, failed_courses: [], created: 1, updated: 0, unchanged: 0 }
    importer = instance_double(Catalog::Importer, call!: counts)
    allow(Catalog::Importer).to receive(:new).and_return(importer)

    expect { expect(described_class.perform_now(term.uid)).to eq(counts) }
      .to have_enqueued_job(Catalog::CourseDetailsSyncJob).with(term.uid)
    expect(term.reload.catalog_importing).to be(false)
  end

  it "shows the term as importing while it runs" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog) do
      expect(term.reload).to have_attributes(catalog_importing: true, catalog_import_failed: false)
      []
    end
    term.update!(catalog_import_failed: true)

    described_class.perform_now(term.uid)

    expect(term.reload).to have_attributes(catalog_importing: false, catalog_import_failed: false)
  end

  it "returns zero counts when Banner lists no courses" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).and_return([])

    expect(described_class.perform_now(term.uid)).to include(created: 0, updated: 0, unchanged: 0)
  end

  it "marks the term as failed and enqueues nothing when Banner fails" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog)
      .and_raise(Catalog::LeopardWebClient::RequestError, "down")

    expect { expect { described_class.perform_now(term.uid) }.to raise_error(Catalog::LeopardWebClient::RequestError, /down/) }
      .not_to have_enqueued_job(Catalog::CourseDetailsSyncJob)
    expect(term.reload).to have_attributes(catalog_import_failed: true, catalog_importing: false)
  end

  describe ".enqueue" do
    it "marks the term as importing before the job is in the queue, and keeps the job id" do
      term.update!(catalog_import_failed: true)

      job = nil
      expect { job = described_class.enqueue(term) }.to have_enqueued_job(described_class).with(term.uid)

      expect(term.reload).to have_attributes(catalog_importing: true, catalog_import_failed: false,
                                             catalog_import_job_id: job.job_id)
    end
  end
end
