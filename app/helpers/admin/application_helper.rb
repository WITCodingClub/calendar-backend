# frozen_string_literal: true

module Admin
  # View helpers for the admin layout and the shared admin partials.
  module ApplicationHelper
    include ::ApplicationHelper
    include ::IconHelper

    # An icon from IconHelper::ICONS. It is decorative, so screen readers skip it.
    def admin_icon(name, css_class: "w-5 h-5")
      icon(name, css_class: css_class)
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
    # A Kaminari collection gets the pagination footer. Pass `card: false` for a
    # table that sits inside an admin/shared/card.
    def admin_table(rows, empty: "Nothing to show yet.", id: nil, paginate: true, card: true, &block)
      table = AdminTableBuilder.new
      capture(table, &block)
      render "admin/shared/data_table", table: table, rows: rows, empty: empty, id: id, card: card,
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

    ADMIN_FLASH_ICONS = { danger: :exclamation, warning: :exclamation, success: :check_circle, info: :information }.freeze

    # How admin/shared/flash shows one flash type: the kind is the tone.
    def admin_flash_style(type)
      kind = flash_kind(type)
      ApplicationHelper::FLASH_BEHAVIOR.fetch(kind).merge(tone: kind, icon: ADMIN_FLASH_ICONS.fetch(kind))
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
end
