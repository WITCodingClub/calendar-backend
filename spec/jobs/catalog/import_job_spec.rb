# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ImportJob do
  let(:term) { create(:term, catalog_importing: true) }

  it "imports the courses, then enqueues the course details sync" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).with(term: term.uid)
                                                                   .and_return({ success: true, courses: [ { crn: 1 } ] })
    importer = instance_double(Catalog::Importer, call!: true)
    allow(Catalog::Importer).to receive(:new).and_return(importer)

    expect { described_class.perform_now(term.uid) }.to have_enqueued_job(Catalog::CourseDetailsSyncJob).with(term.uid)
    expect(term.reload.catalog_importing).to be(false)
  end

  it "marks the term as failed and enqueues nothing when Banner fails" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).and_return({ success: false, error: "down" })

    expect { expect { described_class.perform_now(term.uid) }.to raise_error(RuntimeError, /down/) }
      .not_to have_enqueued_job(Catalog::CourseDetailsSyncJob)
    expect(term.reload.catalog_import_failed).to be(true)
  end
end
