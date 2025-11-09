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
    let(:user) { create(:user) }
    let(:meeting_time) { create(:meeting_time) }
    subject { build(:event_preference, user: user, preferenceable: meeting_time, color_id: 5) }

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
          { "minutes" => 15, "method" => "popup" },
          { "minutes" => 1440, "method" => "email" }
        ]
        expect(subject).to be_valid
      end

      it "rejects non-array reminder settings" do
        subject.reminder_settings = { "minutes" => 15, "method" => "popup" }
        expect(subject).not_to be_valid
      end

      it "rejects reminders without minutes field" do
        subject.reminder_settings = [{ "method" => "popup" }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders without method field" do
        subject.reminder_settings = [{ "minutes" => 15 }]
        expect(subject).not_to be_valid
      end

      it "rejects reminders with invalid method" do
        subject.reminder_settings = [{ "minutes" => 15, "method" => "invalid" }]
        expect(subject).not_to be_valid
      end

      it "accepts 'notification' as an alias for 'popup'" do
        subject.reminder_settings = [{ "minutes" => 15, "method" => "notification" }]
        expect(subject).to be_valid
      end

      it "normalizes 'notification' to 'popup' before save" do
        subject.reminder_settings = [
          { "minutes" => 15, "method" => "notification" },
          { "minutes" => 30, "method" => "popup" },
          { "minutes" => 60, "method" => "email" }
        ]
        subject.save!
        subject.reload

        expect(subject.reminder_settings).to eq([
          { "minutes" => 15, "method" => "popup" },
          { "minutes" => 30, "method" => "popup" },
          { "minutes" => 60, "method" => "email" }
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
