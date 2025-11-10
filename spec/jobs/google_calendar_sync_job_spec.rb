# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarSyncJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }

    it "calls sync_course_schedule on the user with force: false by default" do
      allow(user).to receive(:sync_course_schedule)

      described_class.perform_now(user)

      expect(user).to have_received(:sync_course_schedule).with(force: false)
    end

    it "calls sync_course_schedule on the user with force: true when specified" do
      allow(user).to receive(:sync_course_schedule)

      described_class.perform_now(user, force: true)

      expect(user).to have_received(:sync_course_schedule).with(force: true)
    end

    context "when no course changes have occurred since last sync" do
      let(:oauth_credential) { create(:oauth_credential, user: user) }
      let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential, updated_at: 1.hour.ago) }
      let(:course) { create(:course, updated_at: 2.hours.ago) }
      let!(:enrollment) { create(:enrollment, user: user, course: course) }

      before do
        google_calendar # Ensure google_calendar exists
      end

      it "skips sync and logs a message" do
        expect(Rails.logger).to receive(:info).with(/Skipping sync for user.*no changes since/)
        expect(user).not_to receive(:sync_course_schedule)

        described_class.perform_now(user, force: false)
      end

      it "does not skip when force: true" do
        allow(user).to receive(:sync_course_schedule)
        expect(Rails.logger).not_to receive(:info).with(/Skipping sync/)

        described_class.perform_now(user, force: true)

        expect(user).to have_received(:sync_course_schedule).with(force: true)
      end
    end

    context "when course changes have occurred since last sync" do
      let(:oauth_credential) { create(:oauth_credential, user: user) }
      let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential, updated_at: 2.hours.ago) }
      let(:course) { create(:course, updated_at: 1.hour.ago) }
      let!(:enrollment) { create(:enrollment, user: user, course: course) }

      before do
        google_calendar # Ensure google_calendar exists
      end

      it "performs sync" do
        allow(user).to receive(:sync_course_schedule)
        expect(Rails.logger).not_to receive(:info).with(/Skipping sync/)

        described_class.perform_now(user, force: false)

        expect(user).to have_received(:sync_course_schedule).with(force: false)
      end
    end

    context "when user has no google_calendars" do
      it "performs sync" do
        allow(user).to receive(:sync_course_schedule)
        expect(Rails.logger).not_to receive(:info).with(/Skipping sync/)

        described_class.perform_now(user, force: false)

        expect(user).to have_received(:sync_course_schedule).with(force: false)
      end
    end

    context "when user has no courses" do
      let(:oauth_credential) { create(:oauth_credential, user: user) }
      let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential, updated_at: 1.hour.ago) }

      before do
        google_calendar # Ensure google_calendar exists
      end

      it "performs sync" do
        allow(user).to receive(:sync_course_schedule)
        expect(Rails.logger).not_to receive(:info).with(/Skipping sync/)

        described_class.perform_now(user, force: false)

        expect(user).to have_received(:sync_course_schedule).with(force: false)
      end
    end
  end
end
