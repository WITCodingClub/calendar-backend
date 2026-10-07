# frozen_string_literal: true

# View helpers for the admin layout and the shared admin partials.
module AdminHelper
  # Outline icons (Heroicons v1, MIT). Each value is the `d` of one 24x24 path.
  ICONS = {
    academic_cap: "M12 14l9-5-9-5-9 5 9 5zm0 0l6.16-3.422a12.083 12.083 0 01.665 6.479A11.952 11.952 0 0012 20.055a11.952 11.952 0 00-6.824-2.998 12.078 12.078 0 01.665-6.479L12 14zm-4 6v-7.5l4-2.222",
    adjustments: "M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4",
    arrow_left: "M10 19l-7-7m0 0l7-7m-7 7h18",
    book: "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253",
    building: "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
    calendar: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
    check_circle: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
    chevron_left: "M15 19l-7-7 7-7",
    chevron_right: "M9 5l7 7-7 7",
    clipboard_check: "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4",
    clock: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
    code: "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
    collection: "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10",
    copy: "M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z",
    database: "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4",
    download: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4",
    exclamation: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
    external: "M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14",
    flag: "M3 21v-4m0 0V5a2 2 0 012-2h6.5l1 1H21l-3 6 3 6h-8.5l-1-1H5a2 2 0 00-2 2zm9-13.5V9",
    home: "M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6",
    inbox: "M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4",
    information: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    key: "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
    location: "M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0zM15 11a3 3 0 11-6 0 3 3 0 016 0z",
    logout: "M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1",
    menu: "M4 6h16M4 12h16M4 18h16",
    pencil: "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
    plus: "M12 4v16m8-8H4",
    refresh: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
    search: "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z",
    shield_check: "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
    star: "M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z",
    trash: "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16",
    users: "M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z",
    x: "M6 18L18 6M6 6l12 12"
  }.freeze

  # An outline icon. It is decorative, so screen readers skip it.
  def admin_icon(name, css_class: "w-5 h-5")
    path = ICONS.fetch(name.to_sym)
    tag.svg(class: css_class, fill: "none", stroke: "currentColor", viewBox: "0 0 24 24", "aria-hidden": "true") do
      tag.path("stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: path)
    end
  end

  # The path of a navigation item. Items name a route helper or give a path.
  def admin_nav_path(item)
    item[:path].is_a?(Symbol) ? public_send(item[:path]) : item[:path]
  end

  # True when the current page belongs to the navigation item at `path`. The
  # dashboard matches only itself, because every admin path starts with it.
  def admin_nav_active?(path)
    current = request.path
    return current == path if path == admin_root_path

    current == path || current.start_with?("#{path}/")
  end

  # Badge colors by meaning. Every admin page uses the same tone for the same
  # kind of state, so a color reads the same everywhere.
  BADGE_TONES = {
    neutral: "bg-surface-container-high text-on-surface-variant",
    info: "bg-primary-container text-on-primary-container",
    success: "bg-tertiary-container text-on-tertiary-container",
    warning: "bg-secondary-container text-on-secondary-container",
    danger: "bg-error-container text-on-error-container"
  }.freeze

  # A small rounded label for a state, a type, or a count.
  def admin_badge(text, tone = :neutral, title: nil)
    tag.span(text, title: title, class: [ "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap", BADGE_TONES.fetch(tone.to_sym) ])
  end

  # A table of records. The block declares the columns:
  #
  #   <%= admin_table(@users, empty: "No users match.") do |t| %>
  #     <% t.column("Email") { |user| link_to user.email, admin_user_path(user) } %>
  #     <% t.column("Created", align: :right) { |user| l(user.created_at.to_date) } %>
  #   <% end %>
  #
  # A Kaminari collection gets the pagination footer.
  def admin_table(rows, empty: "Nothing to show yet.", id: nil, paginate: true, &block)
    table = AdminTableBuilder.new
    capture(table, &block)
    render "admin/shared/data_table", table: table, rows: rows, empty: empty, id: id,
                                      paginate: paginate && rows.respond_to?(:total_pages)
  end

  # The HTML for a table cell or a detail value. The block can print ERB or
  # return a value. A blank result shows a muted dash.
  def admin_block_content(block, *args)
    result = nil
    html = capture { result = block.call(*args); nil }
    content = html.presence || (result.is_a?(ActionView::OutputBuffer) ? nil : result.presence)
    return tag.span("—", class: "text-on-surface-variant") if content.blank?

    content.is_a?(String) ? content : content.to_s
  end

  # A list of label and value pairs for a detail page:
  #
  #   <%= admin_details do |d| %>
  #     <% d.item("Email") { @user.email } %>
  #     <% d.item("Notes", wide: true) { simple_format(@user.notes) } %>
  #   <% end %>
  def admin_details(columns: 2, &block)
    list = AdminDetailsBuilder.new
    capture(list, &block)
    render "admin/shared/details", list: list, columns: columns
  end

  # The page numbers to show around the current page. nil marks a gap.
  def admin_page_window(current, total, around: 2)
    pages = [ 1, total, *((current - around)..(current + around)) ].select { |n| n.between?(1, total) }.uniq.sort
    pages.each_with_object([]) do |page, window|
      window << nil if window.any? && page - window.compact.last > 1
      window << page
    end
  end

  # The URL of the current page with a different page number. Filters and
  # search stay in the query string.
  def admin_page_url(page)
    url_for(request.query_parameters.merge("page" => (page if page > 1)).compact)
  end

  # Flash keys map to a tone and an icon. An error stays until it is closed.
  def admin_flash_style(type)
    case type.to_s
    when "alert", "error", "danger" then { tone: :danger, icon: :exclamation, timeout: 0, role: "alert" }
    when "warning" then { tone: :warning, icon: :exclamation, timeout: 0, role: "alert" }
    when "notice", "success" then { tone: :success, icon: :check_circle, timeout: 8000, role: "status" }
    else { tone: :info, icon: :information, timeout: 8000, role: "status" }
    end
  end

  # Collects the columns of an admin_table.
  class AdminTableBuilder
    Column = Struct.new(:label, :block, :align, :css_class, :primary, keyword_init: true)

    attr_reader :columns, :row_class_block

    def initialize
      @columns = []
    end

    # `primary` marks the cell that heads a row when the table stacks into
    # cards on a small screen. The first column is primary by default.
    def column(label, align: :left, css_class: nil, primary: nil, &block)
      @columns << Column.new(label: label, block: block, align: align, css_class: css_class,
                             primary: primary.nil? ? @columns.empty? : primary)
    end

    # Extra classes for a row, such as a highlight for a row that needs action.
    def row_class(&block)
      @row_class_block = block
    end
  end

  # Collects the items of an admin_details list.
  class AdminDetailsBuilder
    Item = Struct.new(:label, :block, :wide, keyword_init: true)

    attr_reader :items

    def initialize
      @items = []
    end

    def item(label, wide: false, &block)
      @items << Item.new(label: label, block: block, wide: wide)
    end
  end
end
