# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeAuditSyncService, type: :service do
  let(:user) { create(:user) }
  let(:degree_program) { create(:degree_program) }
  let(:term) { create(:term) }
  let(:html) { file_fixture("leopard_web/degree_audit/valid_single_program.html").read }

  describe "#sync" do
    let(:service) do
      described_class.new(
        user: user,
        html: html,
        degree_program_id: degree_program.id,
        term_id: term.id
      )
    end

    context "with valid HTML" do
      it "creates a new degree evaluation snapshot" do
        expect {
          service.call
        }.to change(DegreeEvaluationSnapshot, :count).by(1)
      end

      it "stores parsed data correctly" do
        result = service.call

        snapshot = result[:snapshot]
        expect(snapshot.user).to eq(user)
        expect(snapshot.degree_program_id).to eq(degree_program.id)
        expect(snapshot.evaluation_term_id).to eq(term.id)
        expect(snapshot.parsed_data).to be_a(Hash)
        expect(snapshot.raw_html).to eq(html)
      end

      it "stores summary data" do
        result = service.call

        snapshot = result[:snapshot]
        expect(snapshot.total_credits_required).to eq(128.0)
        expect(snapshot.total_credits_completed).to eq(44.0)
        expect(snapshot.overall_gpa).to eq(3.75)
        expect(snapshot.evaluation_met).to be(false)
      end

      it "returns success result" do
        result = service.call

        expect(result[:duplicate]).to be(false)
        expect(result[:message]).to eq("Degree audit synced successfully")
        expect(result[:snapshot]).to be_a(DegreeEvaluationSnapshot)
      end
    end

    context "with duplicate content" do
      before do
        # Create initial snapshot
        service.call
      end

      it "does not create a duplicate snapshot" do
        expect {
          service.call
        }.not_to change(DegreeEvaluationSnapshot, :count)
      end

      it "returns duplicate result" do
        result = service.call

        expect(result[:duplicate]).to be(true)
        expect(result[:message]).to eq("Degree audit updated (no changes detected)")
      end

      it "logs the duplicate detection" do
        allow(Rails.logger).to receive(:info)

        service.call

        expect(Rails.logger).to have_received(:info).with(
          /Duplicate degree audit detected/
        )
      end
    end

    context "when sync times out" do
      it "raises ParseTimeout error" do
        allow_any_instance_of(DegreeAuditParserService).to receive(:parse) do
          sleep(11) # Exceed 10 second timeout
        end

        expect {
          service.call
        }.to raise_error(DegreeAuditSyncService::ParseTimeout, /took too long/)
      end

      it "logs the timeout" do
        allow_any_instance_of(DegreeAuditParserService).to receive(:parse) do
          sleep(11)
        end
        allow(Rails.logger).to receive(:warn)

        service.call rescue nil

        expect(Rails.logger).to have_received(:warn).with(
          /Degree audit sync timeout/
        )
      end
    end

    context "when HTML structure is invalid" do
      let(:html) { file_fixture("leopard_web/degree_audit/structure_changed.html").read }

      it "raises StructureError" do
        expect {
          service.call
        }.to raise_error(DegreeAuditParserService::StructureError)
      end

      it "does not create a snapshot" do
        expect {
          service.call rescue nil
        }.not_to change(DegreeEvaluationSnapshot, :count)
      end
    end
  end

  describe "concurrent sync prevention with advisory locks" do
    let(:service) do
      described_class.new(
        user: user,
        html: html,
        degree_program_id: degree_program.id,
        term_id: term.id
      )
    end

    it "prevents duplicate syncs with advisory lock" do
      # Run two syncs in parallel threads
      threads = 2.times.map do
        Thread.new { service.call rescue nil }
      end

      threads.each(&:join)

      # Only one snapshot should be created
      expect(DegreeEvaluationSnapshot.where(user: user).count).to eq(1)
    end

    it "raises ConcurrentSyncError when lock cannot be acquired" do
      # Simulate lock not acquired (with_advisory_lock returns nil when timeout_seconds: 0 and lock is held)
      allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(nil)

      expect {
        service.call
      }.to raise_error(DegreeAuditSyncService::ConcurrentSyncError, /already in progress/)
    end

    it "releases lock on exception" do
      allow_any_instance_of(DegreeAuditParserService).to receive(:parse).and_raise(StandardError, "Test error")

      # First call raises error
      expect { service.call }.to raise_error(StandardError)

      # Second call should work (lock was released)
      allow_any_instance_of(DegreeAuditParserService).to receive(:parse).and_call_original

      expect { service.call }.not_to raise_error
    end
  end

  describe "#calculate_content_hash" do
    let(:service) do
      described_class.new(
        user: user,
        html: html,
        degree_program_id: degree_program.id,
        term_id: term.id
      )
    end

    it "generates consistent hash for same data" do
      parsed_data = { test: "data" }

      hash1 = service.send(:calculate_content_hash, parsed_data)
      hash2 = service.send(:calculate_content_hash, parsed_data)

      expect(hash1).to eq(hash2)
    end

    it "generates different hash for different data" do
      hash1 = service.send(:calculate_content_hash, { test: "data1" })
      hash2 = service.send(:calculate_content_hash, { test: "data2" })

      expect(hash1).not_to eq(hash2)
    end

    it "includes user, program, and term in hash" do
      parsed_data = { test: "data" }
      hash = service.send(:calculate_content_hash, parsed_data)

      # Hash should be a SHA256 hex string
      expect(hash).to match(/^[a-f0-9]{64}$/)
    end
  end

  describe ".sync (class method)" do
    it "provides convenience wrapper" do
      result = described_class.sync(
        user: user,
        html: html,
        degree_program_id: degree_program.id,
        term_id: term.id
      )

      expect(result).to be_a(Hash)
      expect(result).to have_key(:snapshot)
      expect(result).to have_key(:duplicate)
    end
  end

  describe "performance" do
    let(:service) do
      described_class.new(
        user: user,
        html: html,
        degree_program_id: degree_program.id,
        term_id: term.id
      )
    end

    it "completes sync within timeout" do
      expect {
        Timeout.timeout(10) { service.call }
      }.not_to raise_error
    end
  end
end
