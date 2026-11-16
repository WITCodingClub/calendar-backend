# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars do
  describe ".resync" do
    it "queues one sync with the force the caller asks for" do
      user = create(:user, :with_calendar)

      expect { expect(described_class.resync(user, force: false)).to be(true) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: false).exactly(:once)
    end

    it "queues nothing for a person whose sync reaches no provider" do
      user = create(:user)

      expect { expect(described_class.resync(user, force: true)).to be(false) }
        .not_to have_enqueued_job(CourseCalendars::SyncJob)
    end
  end
end
