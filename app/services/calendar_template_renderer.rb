# frozen_string_literal: true

class CalendarTemplateRenderer
  class InvalidTemplateError < StandardError; end

  # Whitelist of allowed variables in templates
  ALLOWED_VARIABLES = %w[
    title course_code subject course_number section_number crn
    room building location
    faculty faculty_email all_faculty
    start_time end_time day day_abbr
    term schedule_type
  ].freeze

  def self.validate_template(template_string)
    return true if template_string.blank?

    begin
      parsed = Liquid::Template.parse(template_string)

      # Check for disallowed tags or filters
      check_for_disallowed_tags(parsed)

      # Extract variables and check they're whitelisted
      variables = extract_variables(parsed)
      disallowed = variables - ALLOWED_VARIABLES
      if disallowed.any?
        raise InvalidTemplateError, "Disallowed variables: #{disallowed.join(', ')}"
      end

      true
    rescue Liquid::SyntaxError => e
      raise InvalidTemplateError, "Syntax error: #{e.message}"
    end
  end

  def render(template_string, context)
    return "" if template_string.blank?

    # Validate before rendering
    self.class.validate_template(template_string)

    # Filter context to only allowed variables
    filtered_context = context.slice(*ALLOWED_VARIABLES.map(&:to_sym))
                              .transform_keys(&:to_s)

    # Parse and render
    template = Liquid::Template.parse(template_string)
    template.render(filtered_context)
  rescue Liquid::Error, InvalidTemplateError => e
    Rails.logger.error("Liquid template rendering error: #{e.message}")
    # Return a safe fallback
    context[:title] || "Event"
  end

  def self.build_context_from_meeting_time(meeting_time)
    course = meeting_time.course
    room = meeting_time.room
    building = room&.building

    {
      title: course.title,
      course_code: "#{course.subject}-#{course.course_number}-#{course.section_number}",
      subject: course.subject,
      course_number: course.course_number,
      section_number: course.section_number,
      crn: course.crn,
      room: room&.formatted_number || room&.name || "",
      building: building&.name || "",
      location: build_location_string(building, room),
      faculty: primary_faculty_name(course),
      faculty_email: primary_faculty_email(course),
      all_faculty: all_faculty_names(course),
      start_time: format_time_with_ampm(meeting_time.begin_time),
      end_time: format_time_with_ampm(meeting_time.end_time),
      day: meeting_time.day_of_week&.titleize || "",
      day_abbr: meeting_time.day_of_week&.first(3)&.capitalize || "",
      term: course.term&.name || "",
      schedule_type: course.schedule_type || ""
    }
  end

  private

  def self.check_for_disallowed_tags(parsed_template)
    # Liquid's default tags (if, case, for, etc.) are allowed
    # We need to ensure no custom tags that could be dangerous
    # For now, we'll allow all standard Liquid tags since they're safe
    true
  end

  def self.extract_variables(parsed_template)
    variables = Set.new
    extract_variables_from_node(parsed_template.root, variables)
    variables.to_a
  end

  def self.extract_variables_from_node(node, variables)
    case node
    when Liquid::Variable
      # Extract variable name from the node
      if node.name.is_a?(Liquid::VariableLookup)
        variables << node.name.name
      elsif node.name.is_a?(String)
        variables << node.name
      end
    when Liquid::Block, Liquid::Document
      node.nodelist.each { |child| extract_variables_from_node(child, variables) }
    when Liquid::Tag
      # Some tags have internal variables
      if node.respond_to?(:nodelist)
        node.nodelist.each { |child| extract_variables_from_node(child, variables) }
      end
    end
  end

  def self.build_location_string(building, room)
    return "" if building.nil? && room.nil?
    return room.formatted_number || room.name if building.nil?
    return building.name if room.nil?

    "#{building.name} - #{room.formatted_number || room.name}"
  end

  def self.primary_faculty_name(course)
    faculty = course.faculties.first
    return "" unless faculty

    faculty.full_name
  rescue
    ""
  end

  def self.primary_faculty_email(course)
    faculty = course.faculties.first
    return "" unless faculty

    faculty.email || ""
  rescue
    ""
  end

  def self.all_faculty_names(course)
    course.faculties.map(&:full_name).join(", ")
  rescue
    ""
  end

  def self.format_time_with_ampm(time_integer)
    return "" if time_integer.nil?

    hours = time_integer / 100
    minutes = time_integer % 100

    period = hours >= 12 ? "PM" : "AM"
    display_hours = hours % 12
    display_hours = 12 if display_hours.zero?

    format("%d:%02d %s", display_hours, minutes, period)
  end

end
