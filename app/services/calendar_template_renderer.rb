# frozen_string_literal: true

class CalendarTemplateRenderer
  class InvalidTemplateError < StandardError; end

  # Whitelist of allowed variables in templates
  ALLOWED_VARIABLES = %w[
    title course_code subject course_number section_number crn
    room building location
    faculty faculty_email all_faculty
    start_time end_time day day_abbr
    term schedule_type schedule_type_short
    exam_date exam_date_short exam_time_of_day duration
    event_type is_final_exam combined_crns
    summary description category organization academic_term
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
      schedule_type: course.schedule_type&.capitalize || "",
      schedule_type_short: shorthand_schedule_type(course.schedule_type),
      event_type: "class",
      is_final_exam: false,
      exam_date: "",
      exam_date_short: "",
      exam_time_of_day: "",
      duration: "",
      combined_crns: course.crn.to_s
    }
  end

  def self.build_context_from_final_exam(final_exam)
    course = final_exam.course

    # Handle orphan finals (no course linked yet)
    if course.nil?
      return {
        title: "CRN #{final_exam.crn}",
        course_code: final_exam.course_code,
        subject: "",
        course_number: "",
        section_number: "",
        crn: final_exam.crn,
        room: "",
        building: "",
        location: final_exam.location || "",
        faculty: "TBA",
        faculty_email: "",
        all_faculty: "TBA",
        start_time: final_exam.formatted_start_time_ampm,
        end_time: final_exam.formatted_end_time_ampm,
        day: final_exam.exam_date.strftime("%A"),
        day_abbr: final_exam.exam_date.strftime("%a"),
        term: final_exam.term&.name || "",
        schedule_type: "Final Exam",
        schedule_type_short: "Final",
        event_type: "final_exam",
        is_final_exam: true,
        exam_date: final_exam.exam_date.strftime("%B %d, %Y"),
        exam_date_short: final_exam.exam_date.strftime("%m/%d/%Y"),
        exam_time_of_day: final_exam.time_of_day&.capitalize || "",
        duration: "#{final_exam.duration_hours} hours",
        combined_crns: final_exam.combined_crns_display
      }
    end

    {
      title: course.title,
      course_code: final_exam.course_code,
      subject: course.subject,
      course_number: course.course_number,
      section_number: course.section_number,
      crn: final_exam.crn,
      room: "",
      building: "",
      location: final_exam.location || "",
      faculty: final_exam.primary_instructor,
      faculty_email: course.faculties.first&.email || "",
      all_faculty: final_exam.all_instructors,
      start_time: final_exam.formatted_start_time_ampm,
      end_time: final_exam.formatted_end_time_ampm,
      day: final_exam.exam_date.strftime("%A"),
      day_abbr: final_exam.exam_date.strftime("%a"),
      term: course.term&.name || "",
      schedule_type: "Final Exam",
      schedule_type_short: "Final",
      event_type: "final_exam",
      is_final_exam: true,
      exam_date: final_exam.exam_date.strftime("%B %d, %Y"),
      exam_date_short: final_exam.exam_date.strftime("%m/%d/%Y"),
      exam_time_of_day: final_exam.time_of_day&.capitalize || "",
      duration: "#{final_exam.duration_hours} hours",
      combined_crns: final_exam.combined_crns_display
    }
  end

  def self.build_context_from_university_calendar_event(event)
    {
      # Primary fields for university events
      summary: event.summary || "",
      title: event.summary || "", # Alias for consistency with course events
      description: event.description || "",
      location: event.location || "",
      category: event.category || "",
      organization: event.organization || "",
      academic_term: event.academic_term || "",
      term: event.academic_term || "", # Alias for consistency
      event_type: "university_calendar",

      # Time fields
      start_time: format_datetime(event.start_time),
      end_time: format_datetime(event.end_time),
      day: event.start_time&.strftime("%A") || "",
      day_abbr: event.start_time&.strftime("%a") || "",

      # Empty course-related fields (for template compatibility)
      course_code: "",
      subject: "",
      course_number: "",
      section_number: "",
      crn: "",
      room: "",
      building: "",
      faculty: "",
      faculty_email: "",
      all_faculty: "",
      schedule_type: event.category&.titleize || "",
      schedule_type_short: event.category || "",
      is_final_exam: false,
      exam_date: "",
      exam_date_short: "",
      exam_time_of_day: "",
      duration: "",
      combined_crns: ""
    }
  end

  class << self
    def format_time_with_ampm(time_integer)
      return "" if time_integer.nil?

      hours = time_integer / 100
      minutes = time_integer % 100

      period = hours >= 12 ? "PM" : "AM"
      display_hours = hours % 12
      display_hours = 12 if display_hours.zero?

      format("%d:%02d %s", display_hours, minutes, period)
    end

    def shorthand_schedule_type(schedule_type)
      return "" if schedule_type.nil?

      case schedule_type.downcase
      when "laboratory"
        "Lab"
      else
        schedule_type.capitalize
      end
    end

    private

    def format_datetime(datetime)
      return "" if datetime.nil?

      datetime.strftime("%-I:%M %p")
    end

    def check_for_disallowed_tags(parsed_template)
      # Liquid's default tags (if, case, for, etc.) are allowed
      # We need to ensure no custom tags that could be dangerous
      # For now, we'll allow all standard Liquid tags since they're safe
      true
    end

    def extract_variables(parsed_template)
      variables = Set.new
      extract_variables_from_node(parsed_template.root, variables)
      variables.to_a
    end

    def extract_variables_from_node(node, variables)
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

    def build_location_string(building, room)
      return "" if building.nil? && room.nil?
      return room.formatted_number || room.name if building.nil?
      return building.name if room.nil?

      "#{building.name} - #{room.formatted_number || room.name}"
    end

    def primary_faculty_name(course)
      faculty = course.faculties.first
      return "" unless faculty

      faculty.full_name
    rescue
      ""
    end

    def primary_faculty_email(course)
      faculty = course.faculties.first
      return "" unless faculty

      faculty.email || ""
    rescue
      ""
    end

    def all_faculty_names(course)
      course.faculties.map(&:full_name).join(", ")
    rescue
      ""
    end

  end

end
