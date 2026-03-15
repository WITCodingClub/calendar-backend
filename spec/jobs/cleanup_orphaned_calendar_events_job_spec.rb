# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupOrphanedCalendarEventsJob do
  describe "queue assignment" do
    it "is assigned to the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "#perform" do
    let(:orphaned_relation) { instance_double(ActiveRecord::Relation, count: 0) }

    before do
      allow(orphaned_relation).to receive(:includes).and_return(orphaned_relation)
      allow(orphaned_relation).to receive(:find_each)
      allow(GoogleCalendarEvent).to receive(:orphaned).and_return(orphaned_relation)
    end

    context "with dry_run: true" do
      before do
        allow(orphaned_relation).to receive(:count).and_return(5)
      end

      it "returns the event count without deleting anything" do
        result = described_class.perform_now(dry_run: true)

        expect(result[:total]).to eq(5)
        expect(result[:deleted]).to eq(0)
        expect(orphaned_relation).not_to have_received(:find_each)
      end
    end

    context "when there are no orphaned events" do
      it "returns zeroed results without iterating" do
        result = described_class.perform_now

        expect(result[:total]).to eq(0)
        expect(result[:deleted]).to eq(0)
        expect(orphaned_relation).not_to have_received(:find_each)
      end
    end

    context "when there are orphaned events" do
      let(:event) { instance_double(GoogleCalendarEvent, id: 1, google_event_id: "evt_abc", google_calendar: nil) }

      before do
        allow(orphaned_relation).to receive(:count).and_return(1)
        allow(orphaned_relation).to receive(:find_each).and_yield(event)
        allow(event).to receive(:destroy!)
      end

      it "destroys each orphaned event" do
        described_class.perform_now

        expect(event).to have_received(:destroy!)
      end

      it "reports the correct deleted count" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(1)
        expect(result[:errors]).to eq(0)
      end

      context "when an error occurs while deleting an event" do
        before do
          allow(event).to receive(:destroy!).and_raise(StandardError.new("Delete failed"))
        end

        it "increments the error count and continues" do
          result = described_class.perform_now

          expect(result[:errors]).to eq(1)
          expect(result[:deleted]).to eq(0)
        end
      end
    end
  end
end
