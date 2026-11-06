# frozen_string_literal: true

module Dashboard
  # Helpers for the read-only catalog pages (#797). The pages render the
  # hashes of the Catalog:: serializers, so they show what the public API
  # shows.
  module CatalogHelper
    # "COMP 2350" to the path of its course page. The path has no space.
    def dashboard_catalog_course_path(code, **params)
      dashboard_course_path(code.to_s.delete(" "), **params)
    end

    # One node of a prerequisite tree from Catalog::CourseSerializer, as HTML.
    # A course that WIT Calendar knows links to its page. A nested group gets
    # parentheses.
    def catalog_requisite(node, nested: false)
      case node["type"]
      when "and", "or"
        separator = tag.span(" #{node['type']} ", class: "text-on-surface-variant uppercase text-xs font-medium")
        joined = safe_join(node["operands"].map { |operand| catalog_requisite(operand, nested: true) }, separator)
        nested ? safe_join([ "(", joined, ")" ]) : joined
      when "course"
        safe_join([ catalog_requisite_course(node), (tag.span(" (min #{node['min_grade']})", class: "text-xs text-on-surface-variant") if node["min_grade"].present?) ].compact)
      when "test"
        tag.span([ node["name"], node["score"].presence ].compact.join(" "))
      end
    end

    # The current URL with a different page number. The filters stay.
    def dashboard_page_url(page)
      query = request.query_parameters.except("page")
      query["page"] = page if page > 1
      query.empty? ? request.path : "#{request.path}?#{query.to_query}"
    end

    # "4.2 / 5 from 31 ratings", or nil when Rate My Professors has no ratings.
    def rmp_summary(rmp)
      return nil if rmp.nil? || rmp[:avg_rating].nil?

      "#{format('%.1f', rmp[:avg_rating])} / 5 from #{pluralize(rmp[:num_ratings], 'rating')}"
    end

    # The days and times of a section's meetings, one line each:
    # "Mon 10:00 AM – 11:40 AM, WENTW 010".
    def section_meeting_lines(section)
      section[:meeting_times].map do |meeting|
        day   = meeting[:day].to_s.first(3).capitalize.presence || "TBA"
        time  = meeting[:all_day] ? "All day" : "#{meeting[:begin_time_12h]} – #{meeting[:end_time_12h]}"
        place = meeting.dig(:location, :display)
        [ day, time ].join(" ") + (place.present? ? ", #{place}" : "")
      end
    end

    # "4.2", or "–" when there is no value.
    def rating_value(value)
      value.nil? ? "–" : format("%.1f", value)
    end

    # "Lab fee (Undergraduate): $150.00", from one entry of CatalogCourse#fees.
    def catalog_fee(fee)
      label = fee["description"] || "Fee"
      label = "#{label} (#{fee['level']})" if fee["level"]
      "#{label}: #{number_to_currency(fee['amount_cents'].to_i / 100.0)}"
    end

    # "12 of 30 open", or nil when Banner gave no seat counts.
    def seats_line(seats)
      return nil if seats.nil? || seats[:capacity].nil?

      "#{seats[:available].to_i} of #{seats[:capacity]} open"
    end

    # The display name of a university event category.
    def event_category_label(category)
      category.to_s.tr("_", " ").capitalize.presence || "Other"
    end

    # The badge class of a university event category.
    def event_category_badge(category)
      case category
      when "holiday", "study_day", "finals" then "m3-badge-error"
      when "deadline", "registration"       then "m3-badge-tertiary"
      when "term_dates", "academic"         then "m3-badge-primary"
      else "m3-badge-secondary"
      end
    end

    # When a university event happens: "Mon, Nov 9", "Mon, Nov 9 – Wed, Nov 11",
    # or "Mon, Nov 9, 2:00 PM – 3:00 PM".
    def event_time_range(event)
      start_at = event.start_time.in_time_zone
      end_at   = event.end_time.in_time_zone

      if event.all_day?
        # An all-day event ends at midnight after its last day.
        last_day = (end_at - 1.second).to_date
        first    = start_at.strftime("%a, %b %-d")
        last_day > start_at.to_date ? "#{first} – #{last_day.strftime('%a, %b %-d')}" : first
      elsif start_at.to_date == end_at.to_date
        "#{start_at.strftime('%a, %b %-d, %-l:%M %p')} – #{end_at.strftime('%-l:%M %p')}"
      else
        "#{start_at.strftime('%a, %b %-d, %-l:%M %p')} – #{end_at.strftime('%a, %b %-d, %-l:%M %p')}"
      end
    end

    private

    def catalog_requisite_course(node)
      return tag.span(node["code"], class: "whitespace-nowrap") unless node["linked"]

      link_to node["code"], dashboard_catalog_course_path(node["code"]),
              class: "text-primary hover:underline whitespace-nowrap", title: node["title"]
    end
  end
end
