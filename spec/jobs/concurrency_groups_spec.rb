# frozen_string_literal: true

require "rails_helper"

# Solid Queue puts the concurrency group in front of every lock key, and the
# default group is the class name. A rename would then change the key, so an
# old-name job and a new-name job for the same user could run at the same time.
# Every limited job therefore names its group with a fixed string.
RSpec.describe "Job concurrency groups" do
  before(:all) { Rails.application.eager_load! }

  let(:limited_jobs) { ApplicationJob.descendants.select(&:concurrency_key) }

  # Outside contract: jobs already in the queue hold their locks under these
  # strings, so a changed string lets an old and a new job run at once. Add a
  # new limited job here; never change a value.
  let(:groups) do
    {
      Catalog::CourseDataSyncJob => "CourseDataSyncJob",
      Catalog::CourseDetailsSyncJob => "CatalogCourseDetailsSyncJob",
      Catalog::ReimportAllTermsJob => "ReimportAllTermsJob",
      Catalog::SeatRefreshJob => "Catalog::SeatRefreshJob",
      Catalog::SectionLinksSyncJob => "Catalog::SectionLinksSyncJob",
      CourseCalendars::HistoricalSyncJob => "GoogleCalendarHistoricalSyncJob",
      CourseCalendars::SyncJob => "GoogleCalendarSyncJob",
      Courses::ProcessTermJob => "ProcessTermCoursesJob",
      DegreeRequirements::CourseImportJob => "DegreeRequirementsCourseImportJob",
      DegreeRequirements::ImportJob => "DegreeRequirementsImportJob",
      Embeddings::GenerateJob => "EmbeddingsGenerateJob",
      Faculties::UpdateRatingsJob => "UpdateFacultyRatingsJob",
      FinalsSchedules::ProcessJob => "FinalsScheduleProcessJob",
      FriendMeetings::PublishJob => "GoogleCalendarSyncJob",
      FriendMeetings::RemoveJob => "GoogleCalendarSyncJob",
      FriendMeetings::ResumeJob => "GoogleCalendarSyncJob",
      FriendMeetings::UpdateJob => "GoogleCalendarSyncJob",
      MicrosoftGraph::CalendarPlacementJob => "GoogleCalendarSyncJob",
      TermElectives::ImportJob => "TermElectivesImportJob",
      UniversityCalendar::BackfillJob => "UniversityCalendarBackfillJob",
      UniversityCalendar::SyncJob => "UniversityCalendarSyncJob"
    }
  end

  it "keeps the group name of every limited job" do
    expect(limited_jobs.to_h { |job| [ job, job.concurrency_group ] }).to eq(groups)
  end

  # CourseCalendars::UserLock: the jobs that write a user's calendar take one
  # lock, so they never run at the same time for one user.
  describe "the per-user calendar lock" do
    let(:user) { create(:user) }
    let(:meeting) { build_stubbed(:friend_meeting, user: user) }
    let(:expected) { "GoogleCalendarSyncJob/google_calendar_sync_user_#{user.id}" }

    it "gives every job the same group and key for one user" do
      jobs = [
        CourseCalendars::SyncJob.new(user, force: true),
        MicrosoftGraph::CalendarPlacementJob.new(user, "primary"),
        FriendMeetings::PublishJob.new(meeting),
        FriendMeetings::UpdateJob.new(meeting),
        FriendMeetings::RemoveJob.new(meeting),
        FriendMeetings::ResumeJob.new(user)
      ]

      expect(jobs.map(&:concurrency_key)).to all(eq(expected))
      expect(jobs.map { |job| job.class.concurrency_duration }).to all(eq(1.hour))
    end
  end
end
