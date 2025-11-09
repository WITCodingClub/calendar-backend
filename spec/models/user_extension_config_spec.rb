# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  default_color_lab     :string           default("#fbd75b"), not null
#  default_color_lecture :string           default("#46d6db"), not null
#  military_time         :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_user_extension_configs_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserExtensionConfig do
  let(:user) { create(:user) }
  let(:config) { user.user_extension_config }

  describe "associations" do
    it "belongs to a user" do
      expect(config.user).to eq(user)
    end
  end

  describe "callbacks" do
    describe "#sync_calendar_if_colors_changed" do
      before do
        # Stub the job to avoid actual job execution
        allow(GoogleCalendarSyncJob).to receive(:perform_later)
      end

      it "queues a sync job when default_color_lecture changes" do
        config.update!(default_color_lecture: "#ff0000")
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end

      it "queues a sync job when default_color_lab changes" do
        config.update!(default_color_lab: "#00ff00")
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end

      it "queues a sync job when both colors change" do
        config.update!(
          default_color_lecture: "#ff0000",
          default_color_lab: "#00ff00"
        )
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true).once
      end

      it "does not queue a sync job when military_time changes" do
        config.update!(military_time: true)
        expect(GoogleCalendarSyncJob).not_to have_received(:perform_later)
      end

      it "does not queue a sync job when colors don't change" do
        config.update!(default_color_lecture: config.default_color_lecture)
        expect(GoogleCalendarSyncJob).not_to have_received(:perform_later)
      end
    end
  end
end
