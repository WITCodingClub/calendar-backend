# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  notifications_disabled_until :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#
require "rails_helper"

RSpec.describe User do
  describe "DND (Do Not Disturb) mode" do
    let(:user) { create(:user) }

    describe "#notifications_disabled?" do
      it "returns false when notifications_disabled_until is nil" do
        user.notifications_disabled_until = nil
        expect(user.notifications_disabled?).to be false
      end

      it "returns false when notifications_disabled_until is in the past" do
        user.notifications_disabled_until = 1.hour.ago
        expect(user.notifications_disabled?).to be false
      end

      it "returns true when notifications_disabled_until is in the future" do
        user.notifications_disabled_until = 1.hour.from_now
        expect(user.notifications_disabled?).to be true
      end
    end

    describe "#disable_notifications!" do
      it "sets notifications_disabled_until to a far future date when called without duration" do
        user.disable_notifications!

        expect(user.notifications_disabled_until).to be > 50.years.from_now
        expect(user.notifications_disabled?).to be true
      end

      it "sets notifications_disabled_until to the specified duration from now" do
        freeze_time do
          user.disable_notifications!(duration: 2.hours)

          expect(user.notifications_disabled_until).to be_within(1.second).of(2.hours.from_now)
          expect(user.notifications_disabled?).to be true
        end
      end
    end

    describe "#enable_notifications!" do
      it "clears notifications_disabled_until" do
        user.disable_notifications!
        expect(user.notifications_disabled?).to be true

        user.enable_notifications!

        expect(user.notifications_disabled_until).to be_nil
        expect(user.notifications_disabled?).to be false
      end
    end
  end
end
