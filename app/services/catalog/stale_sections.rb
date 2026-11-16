# frozen_string_literal: true

module Catalog
  # When a section's Banner data is old enough to read Banner again.
  # Courses::Processor and the MCP section tools use these rules, and
  # Catalog::SectionRefreshJob does the reading in the background, so the
  # answer to the student does not wait for Banner.
  #
  # Seats are not part of this: Catalog::SeatRefreshJob writes them during
  # registration, and it does not move banner_synced_at.
  module StaleSections
    # The nightly sync (Catalog::CourseDataSyncJob) asks Banner about every
    # section of Term.synced_uids. A section it confirmed within this time is
    # served from the catalog with no Banner request. An older one means the
    # sync missed it.
    FRESH_FOR = 36.hours
    # A section is queued at most once in this time. The key also holds when
    # Banner gives nothing and banner_synced_at does not move. A section that
    # Courses::Processor serves from the catalog and that is older than this
    # gets a refresh.
    REFRESH_AFTER = 6.hours
    # The most sections that one refresh call sends to Banner again.
    LIMIT = 30

    module_function

    def fresh?(course)
      course.banner_synced_at&.after?(FRESH_FOR.ago) || false
    end

    def refresh_due?(course)
      course.banner_synced_at.nil? || course.banner_synced_at.before?(REFRESH_AFTER.ago)
    end

    # Queues the sections of a term with these CRNs that the nightly sync
    # missed. A past term gets no refresh, because the nightly sync leaves it
    # out on purpose, and a cancelled section gets none either.
    #
    # @return [Array<Integer>] the ids it queued
    def refresh(term_uid, crns)
      return [] unless Term.synced_uids.include?(term_uid.to_i)

      ids = Course.joins(:term).where(terms: { uid: term_uid }, crn: crns).where.not(status: :cancelled)
                  .banner_synced_before(FRESH_FOR.ago)
                  .limit(LIMIT).pluck(:id)
      queue(ids)
    end

    # Queues the sections that were not queued in the last REFRESH_AFTER. If
    # the job cannot be queued, the keys go, so the next call tries again.
    #
    # @return [Array<Integer>] the ids it queued
    def queue(ids)
      ids = ids.select { |id| Rails.cache.write(cache_key(id), true, expires_in: REFRESH_AFTER, unless_exist: true) }
      return [] if ids.empty?

      begin
        SectionRefreshJob.perform_later(ids)
      rescue StandardError
        ids.each { |id| Rails.cache.delete(cache_key(id)) }
        raise
      end
      ids
    end

    def cache_key(id) = "catalog/section_refresh/#{id}"
  end
end
