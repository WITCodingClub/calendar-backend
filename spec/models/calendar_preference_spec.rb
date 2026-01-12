# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
#  location_template    :text
#  reminder_settings    :jsonb
#  scope                :integer          not null
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  user_id              :bigint           not null
#
# Indexes
#
#  index_calendar_preferences_on_user_id    (user_id)
#  index_calendar_prefs_on_user_scope_type  (user_id,scope,event_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe CalendarPreference do
  describe "validations" do
    let(:user) { create(:user) }

    context "when scope is event_type" do
      subject { build(:calendar_preference, user: user, scope: :event_type, event_type: "lecture") }

      it "requires event_type to be present" do
        subject.event_type = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:event_type]).to be_present
      end
    end

    context "when scope is global" do
      subject { build(:calendar_preference, user: user, scope: :global, event_type: nil) }

      it "validates absence of event_type" do
        subject.event_type = "lecture"
        expect(subject).not_to be_valid
        expect(subject.errors[:event_type]).to be_present
      end
    end

    context "when scope is uni_cal_category" do
      subject { build(:calendar_preference, user: user, scope: :uni_cal_category, event_type: "holiday") }

      it "requires event_type to be present" do
        subject.event_type = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:event_type]).to be_present
      end

      it "validates event_type is a valid university calendar category" do
        CalendarPreference::UNI_CAL_CATEGORIES.each do |category|
          subject.event_type = category
          expect(subject).to be_valid, "Expected #{category} to be valid"
        end
      end

      it "rejects invalid event_type values" do
        subject.event_type = "invalid_category"
        expect(subject).not_to be_valid
        expect(subject.errors[:event_type]).to be_present
      end
    end

    context "color_id validation" do
      subject { build(:calendar_preference, user: user, scope: :global) }

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
      subject { build(:calendar_preference, user: user, scope: :global) }

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

    context "template syntax validation" do
      subject { build(:calendar_preference, user: user, scope: :global) }

      it "accepts valid Liquid templates" do
        subject.title_template = "{{course_code}}: {{title}}"
        expect(subject).to be_valid
      end

      it "rejects invalid Liquid syntax" do
        subject.title_template = "{{unclosed_tag"
        expect(subject).not_to be_valid
        expect(subject.errors[:title_template]).to be_present
      end

      it "rejects templates with disallowed variables" do
        subject.title_template = "{{invalid_variable}}"
        expect(subject).not_to be_valid
        expect(subject.errors[:title_template]).to include(/Disallowed variables/)
      end
    end

    context "reminder_settings validation" do
      subject { build(:calendar_preference, user: user, scope: :global) }

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

      it "allows empty reminder_settings array (no notifications)" do
        subject.reminder_settings = []
        expect(subject).to be_valid
      end

      it "allows nil reminder_settings" do
        subject.reminder_settings = nil
        expect(subject).to be_valid
      end
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:global_pref) { create(:calendar_preference, user: user, scope: :global) }
    let!(:lecture_pref) { create(:calendar_preference, user: user, scope: :event_type, event_type: "lecture") }
    let!(:lab_pref) { create(:calendar_preference, user: user, scope: :event_type, event_type: "laboratory") }
    let!(:holiday_pref) { create(:calendar_preference, user: user, scope: :uni_cal_category, event_type: "holiday") }
    let!(:deadline_pref) { create(:calendar_preference, user: user, scope: :uni_cal_category, event_type: "deadline") }

    describe ".global_scope" do
      it "returns only global preferences" do
        expect(described_class.global_scope).to eq([global_pref])
      end
    end

    describe ".for_event_type" do
      it "returns preferences for specific event type" do
        expect(described_class.for_event_type("lecture")).to eq([lecture_pref])
      end
    end

    describe ".for_uni_cal_category" do
      it "returns preferences for specific university calendar category" do
        expect(described_class.for_uni_cal_category("holiday")).to eq([holiday_pref])
      end
    end

    describe ".uni_cal_categories_scope" do
      it "returns only university calendar category preferences" do
        expect(described_class.uni_cal_categories_scope).to contain_exactly(holiday_pref, deadline_pref)
      end
    end
  end

  describe "enums" do
    it "defines scope enum" do
      expect(described_class.scopes).to eq({ "global" => 0, "event_type" => 1, "uni_cal_category" => 2 })
    end
  end
end
