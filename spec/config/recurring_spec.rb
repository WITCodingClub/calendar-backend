# frozen_string_literal: true

require "rails_helper"

# Solid Queue only reads recurring.yml in production, so a typo in a class
# name or command shows up there as a failed job, not at boot.
RSpec.describe "config/recurring.yml" do
  tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")

  tasks.each do |key, task|
    it "#{key} points at code that exists" do
      if task["class"]
        expect(task["class"].safe_constantize).to be < ActiveJob::Base
      else
        receiver, method = task.fetch("command").match(/\A([\w:]+)\.(\w+[!?]?)/).captures

        expect(receiver.constantize).to respond_to(method)
      end
    end
  end

  # Jobs that only work while they run on a schedule: each picks up work that
  # an earlier step left (a failed meeting removal, expired rows, changed
  # sections, stale calendars, tokens near expiry). A missing or renamed
  # entry stops that work without any error.
  {
    "friend_meeting_removal_sweep" => [ "FriendMeetings::RemovalSweepJob", "every hour at minute 27" ],
    "remove_expired_records" => [ "Cleanup::ExpiredRecordsJob", "every hour at minute 25" ],
    "nightly_calendar_sync" => [ "CourseCalendars::NightlySyncJob", "every 6 hours" ],
    "course_data_sync" => [ "Catalog::CourseDataSyncJob", "every day at 4am" ],
    "refresh_oauth_tokens" => [ "OauthCredentials::RefreshTokensJob", "every wednesday at 2am" ]
  }.each do |key, (job_class, schedule)|
    it "runs #{job_class} #{schedule}" do
      expect(tasks[key]).to include("class" => job_class, "schedule" => schedule)
    end
  end
end
