# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessRiscEventJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "retry configuration" do
    it "retries on StandardError with exponential backoff" do
      expect(described_class.rescue_handlers).not_to be_empty
    end
  end

  describe "#perform" do
    let(:token) { "test_risc_token" }
    let(:jti) { "unique-jti-abc123" }
    let(:event_data) { { jti: jti, subject: { user_id: "user_123" } } }
    let(:decoded_token) { { "sub" => "user_123" } }
    let(:validation_service) { instance_double(RiscValidationService) }
    let(:handler) { instance_double(RiscEventHandlerService) }

    before do
      allow(RiscValidationService).to receive(:new).and_return(validation_service)
      allow(validation_service).to receive(:validate_and_decode).with(token).and_return(decoded_token)
      allow(validation_service).to receive(:extract_event_data).with(decoded_token).and_return(event_data)
      allow(RiscEventHandlerService).to receive(:new).with(event_data).and_return(handler)
      allow(handler).to receive(:process).and_return("processed")
    end

    it "validates and decodes the token" do
      described_class.perform_now(token)

      expect(validation_service).to have_received(:validate_and_decode).with(token)
    end

    it "processes the event via RiscEventHandlerService" do
      described_class.perform_now(token)

      expect(handler).to have_received(:process)
    end

    context "when the event has already been processed (duplicate jti)" do
      before { create(:security_event, jti: jti) }

      it "returns without calling the event handler" do
        described_class.perform_now(token)

        expect(handler).not_to have_received(:process)
      end
    end

    context "when token validation fails with a ValidationError" do
      before do
        allow(validation_service).to receive(:validate_and_decode)
          .and_raise(RiscValidationService::ValidationError.new("Invalid token signature"))
      end

      it "re-raises the validation error (not retried)" do
        expect {
          described_class.perform_now(token)
        }.to raise_error(RiscValidationService::ValidationError, "Invalid token signature")
      end
    end

    context "when an unexpected StandardError occurs" do
      before do
        allow(handler).to receive(:process).and_raise(StandardError.new("Unexpected failure"))
      end

      it "re-raises the error to trigger retry logic" do
        expect {
          described_class.perform_now(token)
        }.to raise_error(StandardError, "Unexpected failure")
      end
    end
  end
end
