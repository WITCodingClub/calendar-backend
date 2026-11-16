# frozen_string_literal: true

require "rails_helper"

# A rate limit that outlasts the short in-process retries leaves the job. The
# job then goes back in the queue with a wait, and frees its worker thread.
RSpec.describe "Calendar provider jobs on a rate limit" do
  let(:user) { create(:user) }
  let(:provider) { instance_double(GoogleCalendar::Provider) }
  let(:manager) { instance_double(GoogleCalendar::CalendarManager) }
  let(:syncer) { instance_double(CourseCalendars::ScheduleSyncer) }
  let(:error) { Google::Apis::RateLimitError.new("rateLimitExceeded: Rate Limit Exceeded", status_code: 403) }

  before do
    allow(GoogleCalendar::Provider).to receive(:new).and_return(provider)
    allow(GoogleCalendar::CalendarManager).to receive(:new).and_return(manager)
    allow(CourseCalendars::ScheduleSyncer).to receive(:new).and_return(syncer)
  end

  {
    CourseCalendars::SyncJob => -> {
      allow(syncer).to receive(:sync_schedule).and_raise(CourseCalendars::RateLimitError)
      [ user ]
    },
    CourseCalendars::HistoricalSyncJob => -> {
      allow(syncer).to receive(:sync_historical).and_raise(CourseCalendars::RateLimitError)
      [ user ]
    },
    GoogleCalendar::CreateJob => -> {
      allow(provider).to receive(:create_or_get_course_calendar).and_raise(error)
      [ user.id ]
    },
    GoogleCalendar::DeleteJob => -> {
      allow(manager).to receive(:delete_calendar).and_raise(error)
      [ "cal-1" ]
    },
    GoogleCalendar::EventDeleteJob => -> {
      allow(manager).to receive(:delete_event).and_raise(error)
      [ "cal-1", "evt-1" ]
    }
  }.each do |job_class, setup|
    it "puts #{job_class} back in the queue with a wait" do
      args = instance_exec(&setup)

      expect { job_class.perform_now(*args) }.to have_enqueued_job(job_class).with(*args)
    end
  end
end
