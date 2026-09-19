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
# Indexes
#
#  index_user_extension_configs_on_user_id_unique  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserExtensionConfig, type: :model do
  let(:user) { create(:user) }

  # The user model creates a UserExtensionConfig on create; reuse it.
  let(:config) { user.user_extension_config }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "associations and validations" do
    subject { config }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_uniqueness_of(:user_id) }
    it { is_expected.to allow_values("#1a2b3c", "#d50000").for(:default_color_lecture) }
    it { is_expected.to allow_values("#1a2b3c", "#d50000").for(:default_color_lab) }
    it { is_expected.not_to allow_values("banana", "#12345", nil).for(:default_color_lecture) }
    it { is_expected.not_to allow_values("banana", "#12345", nil).for(:default_color_lab) }
    it { is_expected.to normalize(:default_color_lecture, :default_color_lab).from("#1A2B3C").to("#1a2b3c") }
    it { is_expected.to normalize(:default_color_lecture, :default_color_lab).from("5").to("#f6bf26") }
  end

  describe "toggling sync_university_events" do
    before do
      config.update!(
        sync_university_events: true,
        university_event_categories: %w[registration deadline]
      )
    end

    it "preserves selected event types when sync is disabled" do
      config.update!(sync_university_events: false)

      expect(config.reload.university_event_categories).to eq(%w[registration deadline])
    end

    it "retains selected event types after disabling and re-enabling sync" do
      config.update!(sync_university_events: false)
      config.update!(sync_university_events: true)

      expect(config.reload.university_event_categories).to eq(%w[registration deadline])
    end
  end

  describe "#synced_university_event_categories" do
    it "leaves out holidays and categories that no longer sync" do
      config.university_event_categories = %w[holiday deadline campus_event finals]

      expect(config.synced_university_event_categories).to eq(%w[deadline finals])
    end

    it "is empty when no categories are stored" do
      config.university_event_categories = nil

      expect(config.synced_university_event_categories).to eq([])
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
