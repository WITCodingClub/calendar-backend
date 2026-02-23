# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeAuditParserService, type: :service do
  describe "#parse" do
    context "with valid single program HTML" do
      let(:html) { file_fixture("leopard_web/degree_audit/valid_single_program.html").read }
      let(:service) { described_class.new(html: html) }

      it "parses program information correctly" do
        result = service.parse

        expect(result[:program_info]).to include(
          program_code: "BCOS3",
          program_name: "Computer Science - Bachelor of Science",
          catalog_year: "2024-2025",
          evaluation_date: "2026-02-09"
        )
      end

      it "parses requirements correctly" do
        result = service.parse

        expect(result[:requirements]).to be_an(Array)
        expect(result[:requirements].length).to eq(2)

        core_req = result[:requirements].first
        expect(core_req[:area_name]).to eq("Core Requirements")
        expect(core_req[:credits_required]).to eq(48.0)
        expect(core_req[:credits_completed]).to eq(32.0)
        expect(core_req[:status]).to eq("In Progress")
      end

      it "parses courses within requirements" do
        result = service.parse

        core_req = result[:requirements].first
        expect(core_req[:courses]).to be_an(Array)
        expect(core_req[:courses].length).to eq(2)

        first_course = core_req[:courses].first
        expect(first_course).to include(
          subject: "COMP",
          course_number: "1000",
          title: "Introduction to Programming",
          credits: 4.0,
          grade: "A",
          term: "Fall 2024"
        )
      end

      it "parses completed courses" do
        result = service.parse

        expect(result[:completed_courses]).to be_an(Array)
        expect(result[:completed_courses].length).to eq(2)

        first_completed = result[:completed_courses].first
        expect(first_completed).to include(
          subject: "COMP",
          course_number: "1000",
          credits: 4.0,
          grade: "A",
          source: "WIT"
        )
      end

      it "parses in-progress courses" do
        result = service.parse

        expect(result[:in_progress_courses]).to be_an(Array)
        expect(result[:in_progress_courses].length).to eq(1)

        in_progress = result[:in_progress_courses].first
        expect(in_progress).to include(
          subject: "COMP",
          course_number: "3000",
          title: "Algorithms"
        )
      end

      it "parses summary information" do
        result = service.parse

        expect(result[:summary]).to include(
          total_credits_required: 128.0,
          total_credits_completed: 44.0,
          overall_gpa: 3.75,
          requirements_met: false
        )
      end

      it "does not raise an error" do
        expect { service.parse }.not_to raise_error
      end
    end

    context "with transfer credits" do
      let(:html) { file_fixture("leopard_web/degree_audit/with_transfer_credits.html").read }
      let(:service) { described_class.new(html: html) }

      it "identifies transfer courses correctly" do
        result = service.parse

        transfer_course = result[:completed_courses].first
        expect(transfer_course[:source]).to eq("Transfer - Community College")
        expect(transfer_course[:grade]).to eq("T")
        expect(transfer_course[:term]).to eq("Transfer")
      end

      it "distinguishes between transfer and WIT courses" do
        result = service.parse

        sources = result[:completed_courses].pluck(:source)
        expect(sources).to include("Transfer - Community College", "WIT")
      end
    end

    context "with malformed HTML" do
      let(:html) { file_fixture("leopard_web/degree_audit/malformed_html.html").read }
      let(:service) { described_class.new(html: html) }

      it "handles missing fields gracefully" do
        result = service.parse

        # Should not crash, but may have empty/nil values
        expect(result[:program_info][:program_code]).to eq("BCOS3")
        expect(result[:requirements]).to be_an(Array)
      end

      it "handles empty values" do
        result = service.parse

        requirement = result[:requirements].first
        expect(requirement[:area_name]).to be_nil
        expect(requirement[:credits_required]).to be_nil
      end
    end

    context "when HTML structure has changed" do
      let(:html) { file_fixture("leopard_web/degree_audit/structure_changed.html").read }
      let(:service) { described_class.new(html: html) }

      it "raises StructureError with specific missing elements" do
        expect { service.parse }.to raise_error(
          DegreeAuditParserService::StructureError,
          /LeopardWeb HTML structure changed.*Missing/
        )
      end

      it "logs the structure change" do
        allow(Rails.logger).to receive(:error)

        service.parse rescue nil

        expect(Rails.logger).to have_received(:error).with(
          /LeopardWeb HTML structure changed/
        )
      end

      it "sends Sentry notification if available" do
        skip "Sentry not configured in test environment" unless defined?(Sentry)

        expect(Sentry).to receive(:capture_message).with(
          /LeopardWeb HTML structure changed/,
          hash_including(level: :error, tags: hash_including(component: "degree_audit_parser"))
        )

        service.parse rescue nil
      end
    end

    context "with invalid HTML syntax" do
      let(:html) { "<<invalid html>>" }
      let(:service) { described_class.new(html: html) }

      it "raises StructureError (Nokogiri parses it, but required elements are missing)" do
        expect { service.parse }.to raise_error(DegreeAuditParserService::StructureError)
      end
    end
  end

  describe "#validate_html_structure!" do
    context "when structure is valid" do
      let(:html) { file_fixture("leopard_web/degree_audit/valid_single_program.html").read }
      let(:service) { described_class.new(html: html) }

      it "does not raise an error" do
        expect { service.parse }.not_to raise_error
      end
    end

    context "when structure has changed" do
      let(:html) { file_fixture("leopard_web/degree_audit/structure_changed.html").read }
      let(:service) { described_class.new(html: html) }

      it "raises StructureError" do
        expect { service.parse }.to raise_error(DegreeAuditParserService::StructureError)
      end

      it "includes missing elements in error message" do
        begin
          service.parse
        rescue DegreeAuditParserService::StructureError => e
          expect(e.message).to include(".requirement-area")
          expect(e.message).to include(".course-completion")
        end
      end
    end
  end

  describe ".call" do
    let(:html) { file_fixture("leopard_web/degree_audit/valid_single_program.html").read }

    it "provides class method convenience wrapper" do
      result = described_class.new(html: html).call

      expect(result).to be_a(Hash)
      expect(result).to have_key(:program_info)
      expect(result).to have_key(:requirements)
    end
  end

  describe "performance" do
    let(:html) { file_fixture("leopard_web/degree_audit/valid_single_program.html").read }
    let(:service) { described_class.new(html: html) }

    it "parses audit quickly" do
      expect {
        Timeout.timeout(2) { service.parse }
      }.not_to raise_error
    end
  end
end
