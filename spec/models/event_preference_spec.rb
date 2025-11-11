# frozen_string_literal: true

# == Schema Information
#
# Table name: event_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  location_template    :text
#  preferenceable_type  :string           not null
#  reminder_settings    :jsonb
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  preferenceable_id    :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_event_preferences_on_preferenceable     (preferenceable_type,preferenceable_id)
#  index_event_preferences_on_user_id            (user_id)
#  index_event_prefs_on_preferenceable           (preferenceable_type,preferenceable_id)
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe EventPreference do
  describe "validations" do
    subject { build(:event_preference, user: user, preferenceable: meeting_time, color_id: 5) }

    let(:user) { create(:user) }
    let(:meeting_time) { create(:meeting_time) }


    context "color_id validation" do
      it "allows valid color IDs (1-11)" do
        (1..11).each do |color_id|
          subject.color_id = color_id
          expect(subject).to be_valid
        end
      end

      it "rejects invalid color IDs" do
        subject.color_id = 0
        expect(subject).not_to be_valid

        subject.color_id = 12
        expect(subject).not_to be_valid
      end
    end

    context "visibility validation" do
      it "allows valid visibility values" do
        %w[public private default].each do |visibility|
          subject.visibility = visibility
          expect(subject).to be_valid
        end
      end

      it "rejects invalid visibility values" do
        subject.visibility = "invalid"
        expect(subject).not_to be_valid
      end
    end

    context "reminder_settings validation" do
      it "accepts valid reminder settings" do
        subject.reminder_settings = [
          { "time" => "15", "type" => "minutes", "method" => "popup" },
          { "time" => "1", "type" => "days", "method" => "email" }
        ]
        expect(subject).to be_valid
      end

      it "accepts reminder settings with different time units" do
        subject.reminder_settings = [
          { "time" => "30", "type" => "minutes", "method" => "popup" },
          { "time" => "2", "type" => "hours", "method" => "popup" },
          { "time" => "1", "type" => "days", "method" => "email" }
        ]
        expect(subject).to be_valid
      end

      it "rejects non-array reminder settings" do
        subject.reminder_settings = { "time" => "15", "type" => "minutes", "method" => "popup" }
        expect(subject).not_to be_valid
      end

      it "rejects reminders without time field" do
        subject.reminder_settings = [{ "type" => "minutes", "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders without type field" do
        subject.reminder_settings = [{ "time" => "15", "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders without method field" do
        subject.reminder_settings = [{ "time" => "15", "type" => "minutes" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders with invalid method" do
        subject.reminder_settings = [{ "time" => "15", "type" => "minutes", "method" => "invalid" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders with invalid type" do
        subject.reminder_settings = [{ "time" => "15", "type" => "seconds", "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders with non-numeric time" do
        subject.reminder_settings = [{ "time" => "abc", "type" => "minutes", "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders with negative time" do
        subject.reminder_settings = [{ "time" => "-15", "type" => "minutes", "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "accepts 'notification' as an alias for 'popup'" do
        subject.reminder_settings = [{ "time" => "15", "type" => "minutes", "method" => "notification" }]
        expect(subject).to be_valid
      end

      it "normalizes 'notification' to 'popup' before save" do
        subject.reminder_settings = [
          { "time" => "15", "type" => "minutes", "method" => "notification" },
          { "time" => "30", "type" => "minutes", "method" => "popup" },
          { "time" => "1", "type" => "hours", "method" => "email" }
        ]
        subject.save!
        subject.reload

        expect(subject.reminder_settings).to eq([
                                                  { "time" => "15", "type" => "minutes", "method" => "popup" },
                                                  { "time" => "30", "type" => "minutes", "method" => "popup" },
                                                  { "time" => "1", "type" => "hours", "method" => "email" }
                                                ])
      end
    end

    context "at_least_one_preference_set validation" do
      it "requires at least one preference to be set" do
        subject.title_template = nil
        subject.description_template = nil
        subject.location_template = nil
        subject.reminder_settings = nil
        subject.color_id = nil
        subject.visibility = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:base]).to include("At least one preference must be set")
      end

      it "is valid when at least one preference is set" do
        subject.color_id = 5
        expect(subject).to be_valid
      end

      it "is valid when only reminder_settings is set to empty array (no notifications)" do
        subject.title_template = nil
        subject.description_template = nil
        subject.location_template = nil
        subject.reminder_settings = []
        subject.color_id = nil
        subject.visibility = nil
        expect(subject).to be_valid
      end

      it "treats empty array as a set preference (different from nil)" do
        # Empty array = user wants no notifications (valid preference)
        subject_with_empty = build(:event_preference, user: user, preferenceable: meeting_time, reminder_settings: [])
        expect(subject_with_empty).to be_valid

        # nil = user hasn't set anything (invalid if no other preferences)
        subject_with_nil = build(:event_preference, user: user, preferenceable: meeting_time, reminder_settings: nil)
        expect(subject_with_nil).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:meeting_time) { create(:meeting_time) }
    let!(:meeting_pref) { create(:event_preference, user: user, preferenceable: meeting_time) }

    describe ".for_meeting_times" do
      it "returns preferences for meeting times" do
        expect(described_class.for_meeting_times).to include(meeting_pref)
      end
    end
  end
end
