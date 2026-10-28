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
    # instead of reporting one error for each remaining course. Banner stops
    # answering about every 10 minutes, so a full run needs several attempts.
    retry_on Catalog::BannerThrottle::CooldownError, wait: Catalog::BannerThrottle::COOLDOWN + 30.seconds, attempts: 10

    # Each attempt syncs the sections that Banner confirmed longest ago first,
    # across all the terms, and skips a section confirmed more recently than
    # this. So a retry continues where the last attempt stopped, and a night
    # that does not finish leaves the next night to start with the sections it
    # did not reach. Before this, each attempt started again at the first
    # section of the first term. From 2026-10-25 to 2026-10-28 every run
    # stopped on its third cooldown, and no run reached Spring 2027 (#904).
    #
    # Courses::Processor also confirms the sections of a schedule a student
    # uploads, but it does not fetch Banner's linked sections. The window is
    # short so that few of those sections miss the nightly link sync.
    FRESH_FOR = 3.hours

    BATCH_SIZE = 50

    def perform(term_uids: nil)
      term_uids ||= default_term_uids

      return if term_uids.empty?

      terms = Term.where(uid: term_uids).to_a
      missing = term_uids.map(&:to_i) - terms.map(&:uid)
      Rails.logger.warn "[Catalog::CourseDataSyncJob] Terms not found for UIDs #{missing}" if missing.any?
      return if terms.empty?

      Rails.logger.info "[Catalog::CourseDataSyncJob] Starting sync for terms: #{terms.map(&:uid)}"

      counts = sync_courses(terms)
      # The time of a full run, for the MCP advisory (Catalog::Freshness). A
      # run that stops on a Banner cooldown raises before this line.
      Term.where(id: terms.map(&:id)).update_all(sections_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      # Prerequisites and descriptions change rarely. The details job skips a
      # course it fetched for the same term in the last week.
      terms.each { |term| Catalog::CourseDetailsSyncJob.perform_later(term.uid) }

      Rails.logger.info "[Catalog::CourseDataSyncJob] Completed sync for #{terms.length} terms: " \
                        "#{counts[:synced]} synced, #{counts[:errors]} errors"
    end

    private

    # Rooms and times only move for a term that is running or has not started yet.
    # Term.active_uids asks Banner, which lists every term back to 2014. That is
    # about 39,500 courses and 118,000 Banner requests a night, nearly all of them
    # for terms that ended years ago.
    def default_term_uids
      (Term.active.pluck(:uid) + Term.current_and_future.pluck(:uid)).uniq
    end

    def sync_courses(terms)
      counts = { synced: 0, errors: 0 }
      uids = terms.to_h { |term| [ term.id, term.uid ] }

      # find_in_batches ignores an order, so take the ids in order first.
      ids = Course.where(term_id: uids.keys)
                  .where(banner_synced_at: nil).or(Course.where(term_id: uids.keys, banner_synced_at: ...FRESH_FOR.ago))
                  .order(Course.arel_table[:banner_synced_at].asc.nulls_first, :id)
                  .pluck(:id)

      # Courses share buildings and rooms, so one SectionSync (and its
      # Locations) serves them all. Enrollment flags are loaded and marks are
      # sent once for each batch of courses, not once for each course.
      section_sync = Catalog::SectionSync.new

      ids.each_slice(BATCH_SIZE) do |slice|
        courses = Course.where(id: slice).includes(meeting_times: [ :meeting_time_rooms, { rooms: :building } ])
                        .index_by(&:id).values_at(*slice).compact
        flags = CourseCalendars::SyncMarker.enrollment_flags(courses.map(&:id))
        CourseCalendars::SyncMarker.batch_with_enrollment_flags(flags) do
          courses.each do |course|
            # Catalog::BannerThrottle paces the Banner requests, so there is no
            # sleep here.
            counts[:synced] += 1 if section_sync.call(course, uids.fetch(course.term_id))
          rescue Catalog::BannerThrottle::CooldownError
            raise
          rescue => e
            counts[:errors] += 1
            Rails.error.report(e, handled: true, context: { course_id: course.id, crn: course.crn })
          end
        end
      end

      counts
    end
  end
end
