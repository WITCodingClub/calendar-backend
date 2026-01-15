# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendar_events
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  user_edited_fields           :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  final_exam_id                :bigint
#  google_calendar_id           :bigint           not null
#  google_event_id              :string           not null
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_gcal_events_on_calendar_and_uni_event                     (google_calendar_id,university_calendar_event_id)
#  idx_gcal_events_unique_final_exam                             (google_calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_gcal_events_unique_meeting_time                           (google_calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_gcal_events_unique_university                             (google_calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  idx_on_google_calendar_id_meeting_time_id_6c9efabf50          (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_google_calendar_events_on_google_calendar_id            (google_calendar_id)
#  index_google_calendar_events_on_google_event_id               (google_event_id)
#  index_google_calendar_events_on_last_synced_at                (last_synced_at)
#  index_google_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_google_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (final_exam_id => final_exams.id)
#  fk_rails_...  (google_calendar_id => google_calendars.id)
#  fk_rails_...  (meeting_time_id => meeting_times.id)
#  fk_rails_...  (university_calendar_event_id => university_calendar_events.id)
#
require "rails_helper"

RSpec.describe GoogleCalendarEvent do
  describe ".generate_data_hash" do
    let(:base_event_data) do
      {
        summary: "Test Course",
        location: "Room 101",
        start_time: Time.zone.parse("2025-01-15 09:00:00"),
        end_time: Time.zone.parse("2025-01-15 10:30:00"),
        recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO"]
      }
    end

    it "generates a consistent hash for the same data" do
      hash1 = described_class.generate_data_hash(base_event_data)
      hash2 = described_class.generate_data_hash(base_event_data)

      expect(hash1).to eq(hash2)
      expect(hash1).to be_a(String)
      # SHA256 hexdigest produces 64 characters
      expect(hash1.length).to eq(64)
    end

    it "generates different hashes when summary changes" do
      hash1 = described_class.generate_data_hash(base_event_data)
      hash2 = described_class.generate_data_hash(base_event_data.merge(summary: "Different Course"))

      expect(hash1).not_to eq(hash2)
    end

    it "generates different hashes when location changes" do
      hash1 = described_class.generate_data_hash(base_event_data)
      hash2 = described_class.generate_data_hash(base_event_data.merge(location: "Room 202"))

      expect(hash1).not_to eq(hash2)
    end

    it "generates different hashes when times change" do
      hash1 = described_class.generate_data_hash(base_event_data)
      hash2 = described_class.generate_data_hash(
        base_event_data.merge(start_time: Time.zone.parse("2025-01-15 10:00:00"))
      )

      expect(hash1).not_to eq(hash2)
    end

    it "generates different hashes when recurrence changes" do
      hash1 = described_class.generate_data_hash(base_event_data)
      hash2 = described_class.generate_data_hash(
        base_event_data.merge(recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=TU"])
      )

      expect(hash1).not_to eq(hash2)
    end

    context "with preference-controlled fields" do
      it "generates different hashes when reminder_settings changes" do
        hash1 = described_class.generate_data_hash(base_event_data)
        hash2 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "15", "type" => "minutes", "method" => "popup" }]
          )
        )

        expect(hash1).not_to eq(hash2)
      end

      it "generates different hashes when color_id changes" do
        hash1 = described_class.generate_data_hash(base_event_data)
        hash2 = described_class.generate_data_hash(base_event_data.merge(color_id: 5))

        expect(hash1).not_to eq(hash2)
      end

      it "generates different hashes when visibility changes" do
        hash1 = described_class.generate_data_hash(base_event_data)
        hash2 = described_class.generate_data_hash(base_event_data.merge(visibility: "private"))

        expect(hash1).not_to eq(hash2)
      end

      it "handles nil values for preference fields" do
        data_with_nil_prefs = base_event_data.merge(
          reminder_settings: nil,
          color_id: nil,
          visibility: nil
        )

        hash = described_class.generate_data_hash(data_with_nil_prefs)
        expect(hash).to be_a(String)
        # SHA256 hexdigest produces 64 characters
        expect(hash.length).to eq(64)
      end

      it "treats missing and nil preference fields the same" do
        data_without_prefs = base_event_data
        data_with_nil_prefs = base_event_data.merge(
          reminder_settings: nil,
          color_id: nil,
          visibility: nil
        )

        hash1 = described_class.generate_data_hash(data_without_prefs)
        hash2 = described_class.generate_data_hash(data_with_nil_prefs)

        expect(hash1).to eq(hash2)
      end
    end

    context "with complex reminder_settings" do
      it "detects changes in reminder count" do
        hash1 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }]
          )
        )
        hash2 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [
              { "time" => "30", "type" => "minutes", "method" => "popup" },
              { "time" => "1", "type" => "hours", "method" => "email" }
            ]
          )
        )

        expect(hash1).not_to eq(hash2)
      end

      it "detects changes in reminder method" do
        hash1 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }]
          )
        )
        hash2 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "email" }]
          )
        )

        expect(hash1).not_to eq(hash2)
      end

      it "detects changes in reminder time" do
        hash1 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }]
          )
        )
        hash2 = described_class.generate_data_hash(
          base_event_data.merge(
            reminder_settings: [{ "time" => "15", "type" => "minutes", "method" => "popup" }]
          )
        )

        expect(hash1).not_to eq(hash2)
      end
    end
  end

  describe "#data_changed?" do
    let(:event_data) do
      {
        summary: "Test Course",
        location: "Room 101",
        start_time: Time.zone.parse("2025-01-15 09:00:00"),
        end_time: Time.zone.parse("2025-01-15 10:30:00"),
        recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO"],
        reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }],
        color_id: 5,
        visibility: "default"
      }
    end
    let(:event) do
      build(:google_calendar_event,
            event_data_hash: described_class.generate_data_hash(event_data))
    end

    it "returns false when data hasn't changed" do
      expect(event.data_changed?(event_data)).to be false
    end

    it "returns true when summary changes" do
      changed_data = event_data.merge(summary: "Different Course")
      expect(event.data_changed?(changed_data)).to be true
    end

    it "returns true when reminder_settings changes" do
      changed_data = event_data.merge(
        reminder_settings: [{ "time" => "15", "type" => "minutes", "method" => "popup" }]
      )
      expect(event.data_changed?(changed_data)).to be true
    end

    it "returns true when color_id changes" do
      changed_data = event_data.merge(color_id: 11)
      expect(event.data_changed?(changed_data)).to be true
    end

    it "returns true when visibility changes" do
      changed_data = event_data.merge(visibility: "private")
      expect(event.data_changed?(changed_data)).to be true
    end
  end

  describe "#mark_synced!" do
    let(:event) { create(:google_calendar_event) }

    it "updates last_synced_at timestamp" do
      expect { event.mark_synced! }.to(change { event.reload.last_synced_at })
    end
  end

  describe "#needs_sync?" do
    it "returns true when last_synced_at is nil" do
      event = build(:google_calendar_event, last_synced_at: nil)
      expect(event.needs_sync?).to be true
    end

    it "returns true when last_synced_at is older than threshold" do
      event = build(:google_calendar_event, last_synced_at: 2.hours.ago)
      expect(event.needs_sync?(1.hour)).to be true
    end

    it "returns false when last_synced_at is within threshold" do
      event = build(:google_calendar_event, last_synced_at: 30.minutes.ago)
      expect(event.needs_sync?(1.hour)).to be false
    end
  end

  describe "#user_edited?" do
    it "returns false when user_edited_fields is nil" do
      event = build(:google_calendar_event, user_edited_fields: nil)
      expect(event.user_edited?).to be false
    end

    it "returns false when user_edited_fields is empty" do
      event = build(:google_calendar_event, user_edited_fields: [])
      expect(event.user_edited?).to be false
    end

    it "returns true when user_edited_fields has values" do
      event = build(:google_calendar_event, user_edited_fields: %w[summary])
      expect(event.user_edited?).to be true
    end
  end

  describe "#field_edited?" do
    let(:event) { build(:google_calendar_event, user_edited_fields: %w[summary location]) }

    it "returns true for edited fields" do
      expect(event.field_edited?(:summary)).to be true
      expect(event.field_edited?("location")).to be true
    end

    it "returns false for non-edited fields" do
      expect(event.field_edited?(:description)).to be false
      expect(event.field_edited?("start_time")).to be false
    end

    it "returns false when user_edited_fields is nil" do
      event = build(:google_calendar_event, user_edited_fields: nil)
      expect(event).not_to be_field_edited(:summary)
    end
  end

  describe "#mark_fields_edited!" do
    let(:event) { create(:google_calendar_event, user_edited_fields: nil) }

    it "marks a single field as edited" do
      event.mark_fields_edited!(:summary)
      expect(event.reload.user_edited_fields).to eq(%w[summary])
    end

    it "marks multiple fields as edited" do
      event.mark_fields_edited!(%w[summary location])
      expect(event.reload.user_edited_fields).to match_array(%w[summary location])
    end

    it "accumulates edited fields" do
      event.mark_fields_edited!(:summary)
      event.mark_fields_edited!(:location)
      expect(event.reload.user_edited_fields).to match_array(%w[summary location])
    end

    it "does not duplicate fields" do
      event.mark_fields_edited!(:summary)
      event.mark_fields_edited!(:summary)
      expect(event.reload.user_edited_fields).to eq(%w[summary])
    end

    it "only tracks valid fields" do
      event.mark_fields_edited!(%w[summary invalid_field location])
      expect(event.reload.user_edited_fields).to match_array(%w[summary location])
    end
  end

  describe "#clear_edited_fields!" do
    let(:event) { create(:google_calendar_event, user_edited_fields: %w[summary location description]) }

    it "clears all fields when called without arguments" do
      event.clear_edited_fields!
      expect(event.reload.user_edited_fields).to be_nil
    end

    it "clears specific fields when called with arguments" do
      event.clear_edited_fields!(:summary)
      expect(event.reload.user_edited_fields).to match_array(%w[location description])
    end

    it "clears multiple specific fields" do
      event.clear_edited_fields!(%w[summary location])
      expect(event.reload.user_edited_fields).to eq(%w[description])
    end

    it "sets to nil when all fields are cleared" do
      event.clear_edited_fields!(%w[summary location description])
      expect(event.reload.user_edited_fields).to be_nil
    end
  end

  describe ".user_edited scope" do
    let!(:edited_event) { create(:google_calendar_event, user_edited_fields: %w[summary]) }
    let!(:unedited_event) { create(:google_calendar_event, user_edited_fields: nil) }

    it "returns only user-edited events" do
      expect(described_class.user_edited).to contain_exactly(edited_event)
    end
  end

  describe ".not_user_edited scope" do
    let!(:edited_event) { create(:google_calendar_event, user_edited_fields: %w[summary]) }
    let!(:unedited_event) { create(:google_calendar_event, user_edited_fields: nil) }

    it "returns only non-user-edited events" do
      expect(described_class.not_user_edited).to contain_exactly(unedited_event)
    end
  end
end
