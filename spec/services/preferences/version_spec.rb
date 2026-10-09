# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Version do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { allow(CourseCalendars::SyncJob).to receive(:perform_later) }

  it "returns a stable opaque token for unchanged persisted inputs" do
    create(:event_preference, user: user)
    create(:calendar_preference, user: user)

    version = described_class.for(user)

    expect(version).to match(/\A[0-9a-f]{64}\z/)
    expect(described_class.for(user.reload)).to eq(version)
  end

  {
    title_template: "Saved title",
    description_template: "Saved description",
    location_template: "Saved location",
    reminder_settings: [ { "time" => "45", "type" => "minutes", "method" => "popup" } ],
    color_id: "#abcdef",
    visibility: "private"
  }.each do |field, value|
    [ :event_preference, :calendar_preference ].each do |factory|
      it "detects a bulk #{field} edit to a #{factory} without a timestamp change" do
        preference = create(factory, user: user)
        version = described_class.for(user)
        timestamp = preference.updated_at

        preference.class.where(id: preference.id).update_all(field => value)

        expect(preference.reload.updated_at).to eq(timestamp)
        expect(described_class.for(user)).not_to eq(version)
      end
    end
  end

  [ :event_preference, :calendar_preference ].each do |factory|
    it "detects creation and deletion of a #{factory}" do
      empty_version = described_class.for(user)
      preference = create(factory, user: user)
      populated_version = described_class.for(user)

      expect(populated_version).not_to eq(empty_version)

      preference.class.where(id: preference.id).delete_all

      expect(described_class.for(user)).to eq(empty_version)
    end

    it "detects nested reminder changes in a #{factory}" do
      preference = create(factory, user: user,
                          reminder_settings: [ { "time" => "30", "type" => "minutes", "method" => "popup" } ])
      version = described_class.for(user)

      preference.update!(reminder_settings: [ { "time" => "30", "type" => "minutes", "method" => "email" } ])

      expect(described_class.for(user)).not_to eq(version)
    end

    it "distinguishes inherited reminders from disabled reminders in a #{factory}" do
      preference = create(factory, user: user, title_template: "Saved title", reminder_settings: nil)
      version = described_class.for(user)

      preference.update!(reminder_settings: [])

      expect(described_class.for(user)).not_to eq(version)
    end

    it "ignores timestamp-only changes to a #{factory}" do
      preference = create(factory, user: user)
      version = described_class.for(user)

      preference.update_columns(updated_at: preference.updated_at + 1.hour)

      expect(described_class.for(user)).to eq(version)
    end
  end

  [ :default_color_lecture, :default_color_lab ].each do |field|
    it "detects a change to #{field}" do
      version = described_class.for(user)

      user.user_extension_config.update!(field => "#abcdef")

      expect(described_class.for(user)).not_to eq(version)
    end
  end

  it "ignores display-only settings" do
    config = user.user_extension_config
    version = described_class.for(user)

    config.update!(military_time: !config.military_time,
                   advanced_editing: !config.advanced_editing,
                   show_historic_terms: !config.show_historic_terms)

    expect(described_class.for(user)).to eq(version)
  end

  it "detects notification suppression and its expiry without another write" do
    travel_to(Time.zone.local(2026, 10, 7, 12, 0)) do
      enabled_version = described_class.for(user)
      user.update!(notifications_disabled_until: 5.minutes.from_now)
      disabled_version = described_class.for(user)

      expect(disabled_version).not_to eq(enabled_version)

      travel 6.minutes

      expect(described_class.for(user)).to eq(enabled_version)
    end
  end

  it "detects notifications being enabled again" do
    user.disable_notifications!
    version = described_class.for(user)

    user.enable_notifications!

    expect(described_class.for(user)).not_to eq(version)
  end

  it "isolates tokens from another user's preference, color, and notification changes" do
    other_user = create(:user)
    version = described_class.for(user)

    expect(described_class.for(other_user)).not_to eq(version)

    event_preference = create(:event_preference, user: other_user, title_template: "Other title")
    calendar_preference = create(:calendar_preference, user: other_user, title_template: "Other title")
    other_user.user_extension_config.update!(default_color_lecture: "#abcdef", default_color_lab: "#123456")
    other_user.disable_notifications!

    expect(described_class.for(user)).to eq(version)

    event_preference.update!(title_template: "Other edit")
    calendar_preference.update!(reminder_settings: [])
    event_preference.destroy!
    calendar_preference.destroy!

    expect(described_class.for(user)).to eq(version)
  end

  [ :SYSTEM_DEFAULTS, :FINAL_EXAM_DEFAULTS, :UNI_CAL_DEFAULTS, :UNI_CAL_ALL_DAY_REMINDERS, :UNI_CAL_TIMED_REMINDERS ].each do |constant|
    it "detects a change to resolver #{constant}" do
      version = described_class.for(user)
      original = Preferences::Resolver.const_get(constant)
      replacement = [ { "time" => "45", "type" => "minutes", "method" => "popup" } ]
      replacement = original.merge(title_template: "New default title") if original.is_a?(Hash)

      stub_const("Preferences::Resolver::#{constant}", replacement)

      expect(described_class.for(user)).not_to eq(version)
    end
  end
end
