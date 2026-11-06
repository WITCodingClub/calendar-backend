# frozen_string_literal: true

module Catalog
  # Finds university calendar events: upcoming and ongoing events soonest
  # first, or past events newest first. The dashboard events page uses this
  # object.
  #
  # q matches the summary or the location, each word on its own. An unknown
  # category is ignored.
  class UniversityEventQuery
    def initialize(scope = UniversityCalendarEvent.all)
      @scope = scope
    end

    # @return [ActiveRecord::Relation<UniversityCalendarEvent>]
    def call(past: false, category: nil, q: nil)
      # By end time, so an event in progress, such as a break, is upcoming
      # until it ends, and an event is in only one of the two lists.
      now      = Time.current
      relation = past ? @scope.where(end_time: ...now).order(start_time: :desc) : @scope.where(end_time: now..).order(:start_time)
      category = category.presence_in(UniversityCalendarEvent::CATEGORIES)
      # An event with no category shows as "Other", so the filter finds it too.
      relation = relation.where(category: category == "other" ? [ "other", nil, "" ] : category) if category
      q.present? ? search(relation, q.to_s) : relation
    end

    private

    def search(relation, query)
      query.split.reduce(relation) do |scope, word|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
        scope.where("university_calendar_events.summary ILIKE :q OR university_calendar_events.location ILIKE :q", q: pattern)
      end
    end
  end
end
