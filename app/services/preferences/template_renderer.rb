# frozen_string_literal: true

module Preferences
  class TemplateRenderer
    class InvalidTemplateError < StandardError; end

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

    # Strict parsing rejects conditions that lax parsing reads wrongly, such as
    # `&&`, `=`, or a filter in a condition. Rendering checks saved templates in
    # lax mode, so a template saved before strict mode does not start to fail.
    def self.validate_template(template_string, error_mode: :strict)
      return true if template_string.blank?

      begin
        parsed = Liquid::Template.parse(template_string, error_mode: error_mode)
        check_for_disallowed_tags(parsed)

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

    ALLOWED_CONTEXT_KEYS = ALLOWED_VARIABLES.map(&:to_sym).freeze

    # Conditionals only. else and elsif belong to their if, so they are not
    # tags of their own.
    ALLOWED_TAGS = %w[if unless].freeze

    # Pass the user_id when the renderer builds events from saved templates.
    # A saved template that fails then reports the error, so that a template a
    # later rule rejects does not fail without a trace. A preview passes none,
    # because a bad template there is the person's typing, not a fault.
    def initialize(user_id: nil)
      @user_id = user_id
    end

    # An ICS feed poll or a page load builds a new renderer, so one broken
    # template reports at most once a day for each user.
    TEMPLATE_ERROR_REPORT_INTERVAL = 1.day

    def render(template_string, context)
      return "" if template_string.blank?

      filtered_context = context.slice(*ALLOWED_CONTEXT_KEYS)
                                .transform_keys(&:to_s)

      # render! raises an error at render time, such as a comparison of a
      # string with a number. render would write the error text into the title.
      compiled_template(template_string).render!(filtered_context)
    rescue Liquid::Error, InvalidTemplateError => e
      Rails.logger.error("Liquid template rendering error: #{e.message}")
      report_saved_template_error(template_string, e)
      context[:title] || "Event"
    end

    def self.build_context_from_meeting_time(meeting_time)
      course = meeting_time.course
      rooms = meeting_time.rooms.to_a
      room = rooms.first
      building = room&.building

      {
        title: course.title,
        course_code: "#{course.subject}-#{course.course_number}-#{course.section_number}",
        subject: course.subject,
        course_number: course.course_number,
        section_number: course.section_number,
        crn: course.crn,
        room: rooms.map { |r| r.formatted_number || r.name }.compact.join(" / "),
        building: building&.name || "",
        location: build_location_string(building, rooms),
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
          location: final_exam.location_with_names || "",
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
        location: final_exam.location_with_names || "",
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
        summary: event.summary || "",
        title: event.summary || "",
        description: event.description || "",
        location: event.location || "",
        category: event.category || "",
        organization: event.organization || "",
        academic_term: event.term&.name || event.academic_term || "",
        term: event.term&.name || event.academic_term || "",
        event_type: "university_calendar",
        start_time: format_datetime(event.start_time),
        end_time: format_datetime(event.end_time),
        day: event.start_time&.strftime("%A") || "",
        day_abbr: event.start_time&.strftime("%a") || "",
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

      # Templates may only contain plain text, {{ variable }} interpolation,
      # and the conditionals in ALLOWED_TAGS. Other Liquid tags ({% ... %}),
      # such as loops, includes, and assigns, are rejected so a user-supplied
      # template can't loop, exhaust resources, or pull in other content.
      def check_for_disallowed_tags(parsed_template)
        tags = collect_tag_names(parsed_template.root) - ALLOWED_TAGS
        if tags.any?
          raise InvalidTemplateError, "Disallowed tags: #{tags.uniq.join(', ')}"
        end

        true
      end

      def collect_tag_names(node, names = [])
        return names unless node.respond_to?(:nodelist) && node.nodelist

        node.nodelist.each do |child|
          if child.is_a?(Liquid::Tag)
            names << (child.respond_to?(:tag_name) ? child.tag_name : child.class.name.demodulize.underscore)
          end
          collect_tag_names(child, names)
        end

        names
      end

      def extract_variables(parsed_template)
        variables = Set.new
        extract_variables_from_node(parsed_template.root, variables)
        variables.to_a
      end

      def extract_variables_from_node(node, variables)
        case node
        when Liquid::Variable
          if node.name.is_a?(String)
            variables << node.name
          else
            extract_variables_from_operand(node.name, variables)
          end
        when Liquid::If
          # Unless is an If. Its conditions name variables too.
          node.blocks.each { |condition| extract_variables_from_condition(condition, variables) }
          node.nodelist.each { |child| extract_variables_from_node(child, variables) }
        when Liquid::Block, Liquid::Document, Liquid::BlockBody
          node.nodelist.each { |child| extract_variables_from_node(child, variables) }
        when Liquid::Tag
          if node.respond_to?(:nodelist)
            node.nodelist.each { |child| extract_variables_from_node(child, variables) }
          end
        end
      end

      def extract_variables_from_condition(condition, variables)
        return if condition.nil?

        [ condition.left, condition.right ].each { |operand| extract_variables_from_operand(operand, variables) }
        extract_variables_from_condition(condition.child_condition, variables)
      end

      # A lookup can name more variables inside it: `title[secret]` or
      # `(1..secret)`.
      def extract_variables_from_operand(operand, variables)
        case operand
        when Liquid::VariableLookup
          if operand.name.is_a?(String)
            variables << operand.name
          else
            extract_variables_from_operand(operand.name, variables)
          end
          operand.lookups.each { |lookup| extract_variables_from_operand(lookup, variables) }
        when Liquid::RangeLookup
          extract_variables_from_operand(operand.start_obj, variables)
          extract_variables_from_operand(operand.end_obj, variables)
        end
      end

      def build_location_string(building, rooms)
        rooms = Array(rooms).compact
        room_display = rooms.map { |r| r.formatted_number || r.name }.compact.join(" / ")
        return "" if building.nil? && room_display.empty?
        return room_display if building.nil?
        return building.name if room_display.empty?

        "#{building.name} - #{room_display}"
      end

      def primary_faculty_name(course)
        faculty = course.faculties.first
        return "" unless faculty

        faculty.full_name
      rescue => e
        Rails.error.report(e, handled: true, context: { course_id: course.id })
        ""
      end

      def primary_faculty_email(course)
        faculty = course.faculties.first
        return "" unless faculty

        faculty.email || ""
      rescue => e
        Rails.error.report(e, handled: true, context: { course_id: course.id })
        ""
      end

      def all_faculty_names(course)
        course.faculties.map(&:full_name).join(", ")
      rescue => e
        Rails.error.report(e, handled: true, context: { course_id: course.id })
        ""
      end
    end

    private

    # One renderer builds a whole calendar, and its events share a few
    # templates. Check and parse each template once, not twice for every event.
    # A template that fails the check is remembered as that error, so it fails
    # the same way on every event.
    def compiled_template(template_string)
      @compiled_templates ||= {}
      compiled = @compiled_templates[template_string] ||= begin
        self.class.validate_template(template_string, error_mode: :lax)
        Liquid::Template.parse(template_string)
      rescue Liquid::Error, InvalidTemplateError => e
        e
      end

      raise compiled if compiled.is_a?(Exception)

      compiled
    end

    # The report names only the error class. A Liquid message can quote the
    # template, and a template can hold text the person typed.
    def report_saved_template_error(template_string, error)
      return unless @user_id

      @reported_templates ||= Set.new
      return unless @reported_templates.add?(template_string)

      key = "template_errors:#{@user_id}:#{Digest::SHA256.hexdigest(template_string)}"
      return unless Rails.cache.write(key, true, unless_exist: true, expires_in: TEMPLATE_ERROR_REPORT_INTERVAL)

      Rails.error.report(InvalidTemplateError.new("A saved template failed: #{error.class.name}"),
                         handled: true, context: { user_id: @user_id })
    end
  end
end
