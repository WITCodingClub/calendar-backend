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
  def admin_tool(class_name = "", element = "div", **, &)
    return unless current_user&.admin_access?

    concat content_tag(element, class: "admin-tools #{class_name}".strip, **, &)
  end

  def titleize_with_roman_numerals(title)
    # Decode HTML entities first (LeopardWeb returns encoded HTML)
    # e.g., "&amp;" -> "&", "&ndash;" -> "–"
    result = HTMLEntities.new.decode(title.to_s)

    preserved = {}
    counter = 0

    # Preserve acronyms in parentheses (e.g., "(BIM)", "(GIS)")
    result = result.gsub(/\(([A-Z]{2,})\)/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    # Preserve abbreviations like "M.S." or "Ph.D."
    result = result.gsub(/\b([A-Z]\.[A-Z]\.?)/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    # Preserve "3D" and similar digit+letter combinations that are already correct
    result = result.gsub(/\b(\d+[A-Z]+)\b/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    # Remove spaces between digits and SINGLE standalone letters only (e.g., "2 A" -> "2A")
    # Only match if the letter is followed by whitespace or end of string
    result = result.gsub(/(\d)\s+([A-Za-z])(?=\s|$)/, '\1\2')

    # Capitalize first letter of each word while preserving punctuation
    # Also capitalize letters that follow digits (e.g., "1b" in "Calculus 1b")
    result = result.downcase
                   .gsub(/(^|\s)(\w)/) { $1 + $2.upcase } # Capitalize after space or start
                   .gsub(/(\d)([a-z])/i) { $1 + $2.upcase } # Capitalize letters after digits

    # Fix Roman numerals (I, II, III, IV, V, etc.)
    # Match Roman numerals as separate words
    result = result.gsub(/\b(i{1,3}|iv|v|vi{1,3}|ix|x)\b/i) do |match|
      match.upcase
    end

    # Restore preserved patterns (keys are lowercase after downcasing)
    preserved.each do |key, value|
      # After titleize, key becomes "Zzpreserved0Zz" - match case-insensitively
      result = result.gsub(/#{key}/i, value)
    end

    result
  end

  def extract_subject_code(subject)
    # Extract subject code from parentheses (e.g., "Mechanical (MECH)" -> "MECH")
    # Or return the original subject if no parentheses found
    match = subject.match(/\(([^)]+)\)/)
    match ? match[1] : subject
  end

  # Normalize section number by removing spaces between digits and letters
  # e.g., "1 A" -> "1A", "2 B" -> "2B"
  def normalize_section_number(section)
    return nil if section.blank?

    section.strip.gsub(/(\d)\s+([A-Za-z])/, '\1\2').upcase
  end

end
