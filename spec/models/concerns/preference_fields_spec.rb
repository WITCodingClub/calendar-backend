# frozen_string_literal: true

require "rails_helper"

RSpec.describe PreferenceFields do
  describe ".set?" do
    it "counts an empty reminder list as set, because it means no reminders" do
      expect(described_class.set?(:reminder_settings, [])).to be(true)
      expect(described_class.set?(:reminder_settings, nil)).to be(false)
    end

    it "counts a blank value of another field as unset" do
      expect(described_class.set?(:title_template, "")).to be(false)
      expect(described_class.set?(:title_template, "{{title}}")).to be(true)
    end
  end

  describe "#preference_fields_changed?" do
    let(:preference) { create(:calendar_preference, :uni_cal_global) }

    it "is true after a save that changed a preference field" do
      preference.update!(visibility: "private")

      expect(preference).to be_preference_fields_changed
    end

    it "is false after a save that changed only another column" do
      preference.touch # rubocop:disable Rails/SkipsModelValidations

      expect(preference).not_to be_preference_fields_changed
    end
  end
end
