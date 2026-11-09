# frozen_string_literal: true

module Admin
  # View helpers for the admin pages of the degree requirements import (#864).
  module DegreeRequirementsHelper
    STATUS_TONES = { "imported" => :success, "missing" => :warning, "failed" => :danger, "pending" => :neutral }.freeze
    SOURCE_LABELS = { "html" => "HTML", "wayback" => "Wayback", "pdf" => "PDF" }.freeze
    # The lists of the course comparison report (DegreeRequirements::CourseComparison).
    COMPARISON_LABELS = {
      catalog_only: "No section in WIT Calendar",
      banner_only: "Only in Banner",
      title_differs: "Different title",
      credits_differ: "Different credits"
    }.freeze
    COMPARISON_HINTS = {
      catalog_only: "The catalog year prints the course, and WIT Calendar has no section of it in any term it imported. " \
                    "\"Likely taught as\" lists codes with a similar title in the last " \
                    "#{DegreeRequirements::LikelySections::RECENT_YEARS} academic years: " \
                    "a special topics number (COMP 7800), the same number in another subject, or another number.",
      banner_only: "Banner has sections of the course in a term of this catalog year. The catalog year does not print it.",
      title_differs: "Both have the course. The titles differ in more than case and punctuation.",
      credits_differ: "Both have the course. Banner's credits are outside the catalog's credits."
    }.freeze
    SEASON_LABELS = { "fall" => "Fall", "spring" => "Spring", "summer" => "Summer" }.freeze
    LIKELY_KINDS = {
      special_topics: [ "Special topics", :info ],
      same_number: [ "Same number", :warning ],
      other_number: [ "Similar title", :neutral ]
    }.freeze

    # The codes a catalog-only course likely ran under
    # (DegreeRequirements::LikelySections), one line each.
    def likely_sections_cell(matches)
      return tag.span("None found", class: "text-on-surface-variant") if matches.blank?

      safe_join(matches.map do |match|
        label, tone = LIKELY_KINDS.fetch(match.kind)
        tag.div(class: "flex flex-wrap items-center gap-x-2 gap-y-1 py-0.5") do
          safe_join([
            tag.span(match.code, class: "font-medium whitespace-nowrap"),
            tag.span(match.title),
            admin_badge(label, tone),
            tag.span("last #{match.last_term}", class: "text-xs text-on-surface-variant whitespace-nowrap")
          ])
        end
      end)
    end

    # The status of a catalog year. A year with an import in the queue shows
    # that first, because its stored status is from the last import.
    def catalog_year_status_badge(catalog_year, queued: false)
      return admin_badge("Importing…", :info) if queued
      return admin_badge("Not imported") unless catalog_year.persisted?

      admin_badge(catalog_year.status.capitalize, STATUS_TONES.fetch(catalog_year.status, :neutral))
    end

    def catalog_source_label(source)
      SOURCE_LABELS.fetch(source.to_s, source.to_s)
    end

    # "4" or "3-4" credits.
    def credit_range(min, max)
      return nil if min.nil?

      max.nil? || max == min ? min.to_s : "#{min}-#{max}"
    end

    # "Year 1, Fall" for a term of a plan.
    def plan_term_label(term)
      "Year #{term[:year]}, #{SEASON_LABELS.fetch(term[:season].to_s, term[:season].to_s.capitalize)}"
    end
  end
end
