# frozen_string_literal: true

module Preferences
  # Shapes one CourseCalendars::Event with the person's preferences: the
  # title, description and location templates, the reminders, the color, and
  # the visibility. One instance serves one sync, so the resolver and the
  # template renderer load the person's rows once.
  class Applier
    def initialize(user, resolver: Resolver.new(user), renderer: TemplateRenderer.new(user_id: user.id))
      @resolver = resolver
      @renderer = renderer
    end

    def apply(event)
      prefs     = resolver.resolve_for(event.source)
      variables = Context.for(event.source).variables
      changes   = {}

      changes[:summary]     = renderer.render(prefs[:title_template], variables)       if prefs[:title_template].present?
      changes[:description] = renderer.render(prefs[:description_template], variables) if prefs[:description_template].present?
      # A blank variable, such as a placeholder building, leaves a space at an end.
      changes[:location]    = renderer.render(prefs[:location_template], variables).strip if prefs[:location_template].present?

      changes[:reminder_settings] = prefs[:reminder_settings] unless prefs[:reminder_settings].nil?
      # A lowercase "#rrggbb" hex, or nil. Each provider turns it into its own
      # kind of color: a Google event label, or an Outlook category.
      changes[:color_id]   = Colors.normalize(prefs[:color_id])
      changes[:visibility] = prefs[:visibility] if prefs[:visibility].present?

      event.with(**changes)
    end

    # The last change to the preference rows that apply to the record.
    def changed_at_for(record) = resolver.last_changed_at_for(record)

    private

    attr_reader :resolver, :renderer
  end
end
