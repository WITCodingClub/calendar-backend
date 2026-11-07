# frozen_string_literal: true

require "rails_helper"

# A rate limit that outlasts the short in-process retries leaves the job. The
# job then goes back in the queue with a wait, and frees its worker thread.
RSpec.describe "Google Calendar jobs on a rate limit" do
  let(:user) { create(:user) }
  let(:provider) { instance_double(GoogleCalendar::Provider) }
  let(:error) { Google::Apis::RateLimitError.new("rateLimitExceeded: Rate Limit Exceeded", status_code: 403) }

  before { allow(GoogleCalendar::Provider).to receive(:new).and_return(provider) }

  {
    CourseCalendars::SyncJob => -> {
      allow(user).to receive(:sync_course_schedule).and_raise(error)
      [ user ]
    },
    CourseCalendars::HistoricalSyncJob => -> {
      allow(user).to receive(:sync_historical_events).and_raise(error)
      [ user ]
    },
    GoogleCalendar::CreateJob => -> {
      allow(provider).to receive(:create_or_get_course_calendar).and_raise(error)
      [ user.id ]
    },
    GoogleCalendar::DeleteJob => -> {
      allow(provider).to receive(:delete_calendar).and_raise(error)
      [ "cal-1" ]
    },
    GoogleCalendar::EventDeleteJob => -> {
      allow(provider).to receive(:delete_calendar_event).and_raise(error)
      [ "cal-1", "evt-1" ]
    }
  }.each do |job_class, setup|
    it "puts #{job_class} back in the queue with a wait" do
      args = instance_exec(&setup)

      expect { job_class.perform_now(*args) }.to have_enqueued_job(job_class).with(*args)
    end
  end
end
