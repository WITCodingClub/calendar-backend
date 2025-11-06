# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
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
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    let(:user) { create(:user) }

    it { is_expected.to validate_presence_of(:scope) }

    context "when scope is event_type" do
      subject { build(:calendar_preference, user: user, scope: :event_type, event_type: "lecture") }

      it { is_expected.to validate_presence_of(:event_type) }
    end

    context "when scope is global" do
      subject { build(:calendar_preference, user: user, scope: :global, event_type: nil) }

      it "validates absence of event_type" do
        subject.event_type = "lecture"
        expect(subject).not_to be_valid
        expect(subject.errors[:event_type]).to be_present
      end
    end

    it { is_expected.to validate_length_of(:title_template).is_at_most(500) }
    it { is_expected.to validate_length_of(:description_template).is_at_most(2000) }

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
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:global_pref) { create(:calendar_preference, user: user, scope: :global) }
    let!(:lecture_pref) { create(:calendar_preference, user: user, scope: :event_type, event_type: "lecture") }
    let!(:lab_pref) { create(:calendar_preference, user: user, scope: :event_type, event_type: "laboratory") }

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
  end

  describe "enums" do
    it "defines scope enum" do
      expect(described_class.scopes).to eq({ "global" => 0, "event_type" => 1 })
    end
  end
end
