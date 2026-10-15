# frozen_string_literal: true

module McpTools
  # POST /api/calendar_preferences/preview: renders an event template for
  # one of the user's class meetings, without saving it.
  class PreviewTemplate < BaseTool
    tool_name "preview_template"
    title "Preview an event template"
    description "Shows what an event title, description, or location template gives for one of my class " \
                "meetings, without saving it. Use it before update_class_settings or " \
                "update_calendar_settings. Template variables: " \
                "#{Preferences::TemplateRenderer::ALLOWED_VARIABLES.map { |v| "{{#{v}}}" }.join(', ')}."
    requires_scope "settings:read"
    input_schema(
      properties: {
        template:        { type: "string", maxLength: 2000, description: "A Liquid template, for example {{course_code}} {{schedule_type_short}}." },
        meeting_time_id: { type: "string", description: "The meeting time id from my_courses." }
      },
      required: %w[template meeting_time_id]
    )

    def perform(template:, meeting_time_id:)
      authorize user, :show?
      meeting_time = find_my_meeting_time(meeting_time_id)

      Preferences::TemplateRenderer.validate_template(template)
      context = Preferences::TemplateRenderer.build_context_from_meeting_time(meeting_time)

      { template: template, rendered: Preferences::TemplateRenderer.new.render(template, context) }
    rescue Preferences::TemplateRenderer::InvalidTemplateError => e
      raise ToolError, "The template is not valid: #{e.message}"
    end
  end
end
