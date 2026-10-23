# frozen_string_literal: true

module Catalog
  class Catalog::CourseDataSyncJob < ApplicationJob
    queue_as :low

    # SolidQueue calls this key with the job's arguments, so it has to accept them.
    # A bare -> {} raises ArgumentError on any enqueue that passes term_uids.
    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "CourseDataSyncJob"

    # A run covers every course of each active term and takes hours, so the lock
    # lasts as long as the one of Catalog::CourseDetailsSyncJob.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "course_data_sync" }, duration: 6.hours

    # Banner stopped answering, and Catalog::BannerThrottle holds every request
    # for a few minutes. Stop the run and start again after the cooldown,
    # instead of reporting one error for each remaining course.
    retry_on Catalog::BannerThrottle::CooldownError, wait: Catalog::BannerThrottle::COOLDOWN + 30.seconds, attempts: 3

    def perform(term_uids: nil)
      term_uids ||= default_term_uids

      return if term_uids.empty?

      Rails.logger.info "[Catalog::CourseDataSyncJob] Starting sync for terms: #{term_uids}"

      term_uids.each { |uid| sync_term_courses(uid) }
      # Prerequisites and descriptions change rarely. The details job skips a
      # course it fetched for the same term in the last week.
      term_uids.each { |uid| Catalog::CourseDetailsSyncJob.perform_later(uid) }

      Rails.logger.info "[Catalog::CourseDataSyncJob] Completed sync for #{term_uids.length} terms"
    end

    private

    # Rooms and times only move for a term that is running or has not started yet.
    # Term.active_uids asks Banner, which lists every term back to 2014. That is
    # about 39,500 courses and 118,000 Banner requests a night, nearly all of them
    # for terms that ended years ago.
    def default_term_uids
      (Term.active.pluck(:uid) + Term.current_and_future.pluck(:uid)).uniq
    end

    def sync_term_courses(term_uid)
      term = Term.find_by(uid: term_uid)
      unless term
        Rails.logger.warn "[Catalog::CourseDataSyncJob] Term not found for UID #{term_uid}"
        return
      end

      Rails.logger.info "[Catalog::CourseDataSyncJob] Syncing courses for term #{term.name} (#{term_uid})"

      synced_count = 0
      error_count  = 0

      # Courses in a term share buildings and rooms, so one SectionSync (and its
      # Locations) serves them all. Enrollment flags are loaded and marks are sent once for each batch of
      # courses, not once for each course.
      section_sync = Catalog::SectionSync.new

      term.courses.includes(meeting_times: [ :meeting_time_rooms, { rooms: :building } ])
          .find_in_batches(batch_size: 50) do |courses|
        flags = CourseCalendars::SyncMarker.enrollment_flags(courses.map(&:id))
        CourseCalendars::SyncMarker.batch_with_enrollment_flags(flags) do
          courses.each do |course|
            # Catalog::BannerThrottle paces the Banner requests, so there is no
            # sleep here.
            if section_sync.call(course, term_uid)
              synced_count += 1
            end
          rescue Catalog::BannerThrottle::CooldownError
            raise
          rescue => e
            error_count += 1
            Rails.error.report(e, handled: true, context: { course_id: course.id, crn: course.crn })
          end
        end
      end

      # The time of a full run, for the MCP advisory (Catalog::Freshness). A
      # run that stops on a Banner cooldown raises before this line.
      term.update_column(:sections_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info "[Catalog::CourseDataSyncJob] Term #{term.name} complete — #{synced_count} synced, #{error_count} errors"
    end
  end
end
