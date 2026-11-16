# frozen_string_literal: true

module ApplicationHelper
  SITE_NAME = "WIT Calendar"

  # The name of the page. A view sets it with `content_for :title`.
  def page_title(default = nil)
    content_for?(:title) ? content_for(:title) : default
  end

  # The text for the browser tab. It always ends with the site name.
  def browser_title(default = nil)
    safe_join([ page_title(default), SITE_NAME ].compact_blank, " — ")
  end

  # A JSON-LD script tag that describes the page to search engines.
  #
  # Safe to mark: json_escape turns <, >, and & into \u escapes, so no value
  # can close the tag. HTML escaping would break the JSON, because a browser
  # does not decode entities inside a script tag. The nonce keeps the tag
  # inside the Content Security Policy.
  def structured_data_tag(data)
    tag.script(json_escape(data.to_json).html_safe, type: "application/ld+json", nonce: content_security_policy_nonce) # rubocop:disable Rails/OutputSafety
  end

  # Errors and warnings use role="alert" and stay until closed. The others
  # close after 8 seconds.
  FLASH_BEHAVIOR = {
    danger:  { role: "alert",  timeout: 0 },
    warning: { role: "alert",  timeout: 0 },
    success: { role: "status", timeout: 8000 },
    info:    { role: "status", timeout: 8000 }
  }.freeze

  # The colors and icon of each kind on the dashboard and sign-in pages. Each
  # kind has its own color and icon, so color is not the only cue.
  FLASH_LOOKS = {
    danger:  { css_class: "bg-error-container border-error text-on-error-container", icon: :exclamation_circle },
    warning: { css_class: "bg-primary-container border-primary text-on-primary-container", icon: :exclamation },
    success: { css_class: "bg-tertiary-container border-tertiary text-on-tertiary-container", icon: :check_circle },
    info:    { css_class: "bg-surface-container-high border-outline text-on-surface", icon: :information }
  }.freeze

  # The kind of a flash type: :danger, :warning, :success, or :info.
  def flash_kind(type)
    case type.to_s
    when "alert", "error", "danger" then :danger
    when "warning" then :warning
    when "notice", "success" then :success
    else :info
    end
  end

  # How shared/flash_messages shows one flash type.
  def flash_style(type)
    kind = flash_kind(type)
    FLASH_BEHAVIOR.fetch(kind).merge(FLASH_LOOKS.fetch(kind))
  end

  # The URL of the current page with a different page number. Filters and
  # search stay in the query string.
  #
  # The query goes into the query string only. Do not pass it to url_for:
  # url_for reads keys such as script_name, host, and anchor as link options,
  # so a crafted query could point the page links to a different host.
  def page_url(page)
    query = request.query_parameters.except("page")
    query["page"] = page if page > 1
    query.empty? ? request.path : "#{request.path}?#{query.to_query}"
  end

  # "4 of 24 open" from a pair of Banner counts, or nil when Banner gave no
  # counts. An over-enrolled section has a negative number of open seats, and
  # it is shown as Banner gives it.
  def open_seats_text(available, capacity)
    return nil if available.nil? || capacity.nil?

    "#{available} of #{capacity} open"
  end

  # "Follett Access (Undergraduate): $95.00" for one entry of CatalogCourse#fees.
  def fee_text(fee)
    label = fee["description"] || "Fee"
    label = "#{label} (#{fee['level']})" if fee["level"]
    "#{label}: #{number_to_currency(fee['amount_cents'].to_i / 100.0)}"
  end
end
