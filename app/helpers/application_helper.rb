# frozen_string_literal: true

module ApplicationHelper
  # Renders admin-only content in views.
  # Non-admins see nothing; admins see the content wrapped in a customizable element.
  #
  # @param class_name [String] Additional CSS classes to add to the wrapper
  # @param element [String] The HTML element to use as wrapper (default: "div")
  # @param options [Hash] Additional HTML attributes (data:, id:, etc.)
  # @yield The admin-only content to render
  #
  # @example Basic usage
  #   <% admin_tool do %>
  #     <%= link_to "Edit", edit_admin_path(@resource) %>
  #   <% end %>
  #
  # @example With CSS classes
  #   <% admin_tool("w-fit bg-red-50 p-2 rounded") do %>
  #     <p>Admin-only debugging info</p>
  #   <% end %>
  #
  # @example Different wrapper element
  #   <% admin_tool("inline-flex gap-2", "span") do %>
  #     <span>Admin badge</span>
  #   <% end %>
  def admin_tool(class_name = "", element = "div", **options, &block)
    return unless current_user&.admin_access?

    concat content_tag(element, class: "admin-tools #{class_name}".strip, **options, &block)
  end

  def titleize_with_roman_numerals(title)
    # First, remove spaces between digits and letters (e.g., "2 A" -> "2A")
    cleaned = title.gsub(/(\d)\s+([A-Za-z])/, '\1\2')
    
    # Capitalize first letter of each word while preserving punctuation
    # Also capitalize letters that follow digits (e.g., "1b" in "Calculus 1b")
    titleized = cleaned.downcase
                       .gsub(/(^|\s)(\w)/) { $1 + $2.upcase } # Capitalize after space or start
                       .gsub(/(\d)([a-z])/i) { $1 + $2.upcase } # Capitalize letters after digits

    # Then fix Roman numerals (I, II, III, IV, V, etc.)
    # Match Roman numerals as separate words
    titleized.gsub(/\b(i{1,3}|iv|v|vi{1,3}|ix|x)\b/i) do |match|
      match.upcase
    end
  end

  def extract_subject_code(subject)
    # Extract subject code from parentheses (e.g., "Mechanical (MECH)" -> "MECH")
    # Or return the original subject if no parentheses found
    match = subject.match(/\(([^)]+)\)/)
    match ? match[1] : subject
  end

end
