# frozen_string_literal: true

require "rails_helper"

# Solid Queue puts the concurrency group in front of every lock key, and the
# default group is the class name. A rename would then change the key, so an
# old-name job and a new-name job for the same user could run at the same time.
# Every limited job therefore names its group with a fixed string.
RSpec.describe "Job concurrency groups" do
  before(:all) { Rails.application.eager_load! }

  let(:limited_jobs) { ApplicationJob.descendants.select(&:concurrency_key) }

  it "has jobs with a concurrency limit" do
    expect(limited_jobs).not_to be_empty
  end

  it "gives every limited job a fixed group name, not the class name default" do
    limited_jobs.each do |job|
      expect(job.concurrency_group).to be_a(String), "#{job.name} uses the default group"
    end
  end

  it "keeps the jobs that write a user's calendar in the group of CourseCalendars::SyncJob" do
    writers = [ FriendMeetings::PublishJob, FriendMeetings::RemoveJob, FriendMeetings::ResumeJob,
                FriendMeetings::UpdateJob, MicrosoftGraph::CalendarPlacementJob ]

    expect(writers.map(&:concurrency_group).uniq).to eq([ "GoogleCalendarSyncJob" ])
    expect(CourseCalendars::SyncJob.concurrency_group).to eq("GoogleCalendarSyncJob")
  end
end
