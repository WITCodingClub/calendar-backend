# frozen_string_literal: true

module Admin
  # The numbers on the admin home page. Each method runs a small number of
  # queries, so the page stays fast as the tables grow.
  class Dashboard
    RECENT_SIGN_UPS = 8
    RECENT_FAILED_JOBS = 5

    def initialize(user)
      @user = user
    end

    def counts
      @counts ||= {
        users: User.count,
        calendars: CourseCalendar.count,
        courses: Course.count,
        faculty: Faculty.count,
        terms: Term.count,
        rmp_ratings: RmpRating.count,
        final_exams: FinalExam.count,
        university_events: UniversityCalendarEvent.count
      }
    end

    def sign_ups_this_week
      @sign_ups_this_week ||= User.where(created_at: 7.days.ago..).count
    end

    def recent_sign_ups
      @recent_sign_ups ||= User.order(created_at: :desc).limit(RECENT_SIGN_UPS).to_a
    end

    # Calendar sync health. A calendar is stale when its last sync is older
    # than CourseCalendar::STALE_AFTER, or it never synced.
    def sync_health
      @sync_health ||= begin
        total = counts[:calendars]
        stale = CourseCalendar.stale(CourseCalendar::STALE_AFTER).count
        {
          total: total,
          healthy: total - stale,
          stale: stale,
          never_synced: CourseCalendar.where(last_synced_at: nil).count,
          last_synced_at: CourseCalendar.maximum(:last_synced_at),
          users_needing_sync: User.needs_sync.count,
          revoked_credentials: OauthCredential.revoked.count
        }
      end
    end

    # :ok, :warning, or :danger for the sync health card.
    def sync_status
      health = sync_health
      return :ok if health[:total].zero? || health[:stale].zero?

      health[:stale] * 10 > health[:total] ? :danger : :warning
    end

    def failed_jobs_count
      @failed_jobs_count ||= SolidQueue::FailedExecution.count
    end

    # Job errors can hold user data and tokens, so only a super admin sees
    # them. Other admins see the count.
    def show_job_errors?
      @user.super_admin_access?
    end

    def recent_failed_jobs
      return [] unless show_job_errors?

      @recent_failed_jobs ||= SolidQueue::FailedExecution.includes(:job).order(created_at: :desc).limit(RECENT_FAILED_JOBS).to_a
    end

    # Work that waits on an admin. Each entry has a label, a count, and a path
    # helper name. Only entries with a count above zero, on pages the user
    # can open, are kept.
    def attention
      @attention ||= [
        { label: "Professors missing RMP IDs", count: Faculty.with_courses.where(rmp_id: nil).count, path: :missing_rmp_ids_admin_faculties_path },
        ({ label: "Failed catalog imports", count: Term.where(catalog_import_failed: true).count, path: :admin_course_catalog_path } if NavigationRegistry.item_for(@user, :course_catalog)),
        { label: "Failed finals schedules", count: FinalsSchedule.failed.count, path: :admin_finals_schedules_path },
        { label: "Users waiting for a calendar sync", count: sync_health[:users_needing_sync], path: :admin_users_path }
      ].compact.select { |entry| entry[:count].positive? }
    end
  end
end
