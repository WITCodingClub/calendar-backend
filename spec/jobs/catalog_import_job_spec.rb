# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:term_uid) { "202501" }
    let(:courses) { [{ crn: "12345", title: "Test Course" }] }

    context "when the catalog fetch succeeds" do
      before do
        allow(LeopardWebService).to receive(:get_course_catalog)
          .with(term: term_uid)
          .and_return({ success: true, courses: courses })
      end

      it "passes the fetched courses to CatalogImportService" do
        service_double = instance_double(CatalogImportService)
        allow(CatalogImportService).to receive(:new).with(courses).and_return(service_double)
        allow(service_double).to receive(:call!)

        described_class.perform_now(term_uid)

        expect(CatalogImportService).to have_received(:new).with(courses)
        expect(service_double).to have_received(:call!)
      end
    end

    context "when the catalog fetch fails" do
      before do
        allow(LeopardWebService).to receive(:get_course_catalog)
          .with(term: term_uid)
          .and_return({ success: false, error: "Service unavailable" })
      end

      it "raises an error with the fetch failure reason" do
        expect {
          described_class.perform_now(term_uid)
        }.to raise_error(RuntimeError, /Failed to fetch course catalog/)
      end

      it "does not call CatalogImportService" do
        allow(CatalogImportService).to receive(:new)

        expect { described_class.perform_now(term_uid) }.to raise_error(RuntimeError)
        expect(CatalogImportService).not_to have_received(:new)
      end
    end

    context "when no courses are returned for the term" do
      before do
        allow(LeopardWebService).to receive(:get_course_catalog)
          .with(term: term_uid)
          .and_return({ success: true, courses: [] })
      end

      it "returns without calling CatalogImportService" do
        allow(CatalogImportService).to receive(:new)

        described_class.perform_now(term_uid)

        expect(CatalogImportService).not_to have_received(:new)
      end
    end
  end
end
