# frozen_string_literal: true

module DegreeRequirements
  # Reads the Double Leopard page on wit.edu (DOUBLE_LEOPARD_URL). The
  # catalog does not list these master's programs. A Wentworth senior in any
  # bachelor's program can apply to one of them, and take graduate courses
  # in the senior year.
  #
  # names are the link texts under the "Double Leopard Programs" heading,
  # such as "Computer Science" or "Architecture & Construction Management
  # Dual Degree". max_shared_courses is the number in "Take up to two courses
  # during your senior year", or nil when the page does not say.
  class DoubleLeopardParser
    require "nokogiri"

    HEADING = /double leopard programs/i
    SHARED_COURSES = /up to (\w+) (?:graduate )?courses/i
    NUMBERS = %w[zero one two three four five six].freeze

    def initialize(html)
      @doc = Nokogiri::HTML(html)
    end

    # The link texts from the heading to the next h2, once each. Only links
    # to a program page (/academics/) count, so a "Request info" button does
    # not.
    def names
      found = false
      @doc.css("h2, a[href]").each_with_object([]) do |node, names|
        if node.name == "h2"
          break names if found

          found = node.text.match?(HEADING)
        elsif found && node["href"].include?("/academics/")
          name = node.text.squish
          names << name if name.present? && names.exclude?(name)
        end
      end
    end

    def max_shared_courses
      value = @doc.text.squish[SHARED_COURSES, 1]&.downcase
      return nil if value.nil?

      NUMBERS.index(value) || Integer(value, exception: false)
    end
  end
end
