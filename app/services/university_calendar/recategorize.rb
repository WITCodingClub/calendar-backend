# frozen_string_literal: true

module UniversityCalendar
  # Infers the category of every stored event again with Category. The weekly
  # import does this only for events the feed still lists, so a rule change in
  # Category needs this for the rest. Run it with
  # `bin/rails university_calendar:recategorize`.
  class Recategorize
    Change = Data.define(:event_id, :summary, :from, :to)

    # Rows an admin added by hand, which no feed holds. Their category is the
    # admin's choice, so the task leaves it.
    MANUAL_UID_PREFIX = "manual:"

    def self.call(apply:) = new.call(apply:)

    # Returns the changes. With apply: true it saves them and queues the
    # calendar syncs, the same as an import that changes these categories.
    def call(apply:)
      rows = UniversityCalendarEvent.where.not("ics_uid LIKE ?", "#{MANUAL_UID_PREFIX}%")
      changes = rows.find_each.filter_map do |event|
        category = Category.infer(event.summary, event.event_type_raw)
        Change.new(event_id: event.id, summary: event.summary, from: event.category, to: category) if category != event.category
      end
      return changes unless apply && changes.any?

      UniversityCalendarEvent.transaction do
        changes.each { |change| UniversityCalendarEvent.find(change.event_id).update!(category: change.to) }
      end
      SyncJob.resync_users(changes.flat_map { |change| [ change.from, change.to ] }.compact.uniq)
      changes
    end
  end
end
