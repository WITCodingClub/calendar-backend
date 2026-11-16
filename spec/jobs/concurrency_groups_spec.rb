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
  # groups, so a changed group lets an old and a new job run at once. Solid
  # Queue frees a lock when its duration ends, even while the job still runs,
  # so a shorter duration lets a second job with the same key start. Add a new
  # limited job here; change a value only on purpose.
  let(:locks) do
    {
      Catalog::CourseDataSyncJob => [ "CourseDataSyncJob", 1, 6.hours ],
      Catalog::CourseDetailsSyncJob => [ "CatalogCourseDetailsSyncJob", 1, 6.hours ],
      Catalog::ReimportAllTermsJob => [ "ReimportAllTermsJob", 1, 3.minutes ],
      Catalog::SeatRefreshJob => [ "Catalog::SeatRefreshJob", 1, 15.minutes ],
      Catalog::SectionLinksSyncJob => [ "Catalog::SectionLinksSyncJob", 1, 2.hours ],
      CourseCalendars::HistoricalSyncJob => [ "GoogleCalendarHistoricalSyncJob", 1, 1.hour ],
      CourseCalendars::SyncJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      Courses::ProcessTermJob => [ "ProcessTermCoursesJob", 1, 1.hour ],
      DegreeRequirements::CourseImportJob => [ "DegreeRequirementsCourseImportJob", 1, 1.hour ],
      DegreeRequirements::ImportJob => [ "DegreeRequirementsImportJob", 1, 1.hour ],
      Embeddings::GenerateJob => [ "EmbeddingsGenerateJob", 1, 10.minutes ],
      Faculties::UpdateRatingsJob => [ "UpdateFacultyRatingsJob", 1, 30.minutes ],
      FinalsSchedules::ProcessJob => [ "FinalsScheduleProcessJob", 1, 3.minutes ],
      FriendMeetings::PublishJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      FriendMeetings::RemoveJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      FriendMeetings::ResumeJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      FriendMeetings::UpdateJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      MicrosoftGraph::CalendarPlacementJob => [ "GoogleCalendarSyncJob", 1, 1.hour ],
      TermElectives::ImportJob => [ "TermElectivesImportJob", 1, 30.minutes ],
      UniversityCalendar::BackfillJob => [ "UniversityCalendarBackfillJob", 1, 3.minutes ],
      UniversityCalendar::SyncJob => [ "UniversityCalendarSyncJob", 1, 3.minutes ]
    }
  end

  it "keeps the group, limit, and lock duration of every limited job" do
    actual = limited_jobs.to_h { |job| [ job, [ job.concurrency_group, job.concurrency_limit, job.concurrency_duration ] ] }

    expect(actual).to eq(locks)
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
