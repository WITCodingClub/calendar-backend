# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
#
#  id                          :bigint           not null, primary key
#  advanced_editing            :boolean          default(FALSE), not null
#  default_color_lab           :string           default("#f6bf26"), not null
#  default_color_lecture       :string           default("#039be5"), not null
#  enrolled_terms              :jsonb            not null
#  military_time               :boolean          default(FALSE), not null
#  show_historic_terms         :boolean          default(TRUE), not null
#  sync_university_events      :boolean          default(FALSE), not null
#  university_event_categories :jsonb
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  user_id                     :bigint           not null
#
require "rails_helper"

RSpec.describe UserExtensionConfig, type: :model do
  let(:user) do
    User.create!(
      email: "config-spec@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # The user model creates a UserExtensionConfig on create; reuse it.
  let(:config) { user.user_extension_config }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "toggling sync_university_events" do
    before do
      config.update!(
        sync_university_events: true,
        university_event_categories: %w[campus_event deadline]
      )
    end

    it "preserves selected event types when sync is disabled" do
      config.update!(sync_university_events: false)

      expect(config.reload.university_event_categories).to eq(%w[campus_event deadline])
    end

    it "retains selected event types after disabling and re-enabling sync" do
      config.update!(sync_university_events: false)
      config.update!(sync_university_events: true)

      expect(config.reload.university_event_categories).to eq(%w[campus_event deadline])
    end
  end

  describe "sync_calendar_if_settings_changed" do
    it "enqueues a forced calendar sync when sync_university_events changes" do
      config.update!(sync_university_events: true)

      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
    end

    it "enqueues a forced calendar sync when university_event_categories changes" do
      config.update!(sync_university_events: true)
      config.update!(university_event_categories: %w[finals])

      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true).twice
    end
  end
end
