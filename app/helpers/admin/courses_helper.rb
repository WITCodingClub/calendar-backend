# frozen_string_literal: true

module Admin
  # View helpers for the admin course page.
  module CoursesHelper
    # "4 of 24 open" from a pair of Banner counts. An over-enrolled section
    # has a negative number of open seats, and it is shown as Banner gives it.
    # nil when Banner gave no counts.
    def admin_open_count(available, capacity)
      return nil if available.nil? || capacity.nil?

      "#{available} of #{capacity} open"
    end

    # "Follett Access (Undergraduate): $95.00" for one fee in CatalogCourse#fees.
    def admin_fee(fee)
      label = fee["description"] || "Fee"
      label = "#{label} (#{fee['level']})" if fee["level"]
      "#{label}: #{number_to_currency(fee['amount_cents'] / 100.0)}"
    end
  end
end
