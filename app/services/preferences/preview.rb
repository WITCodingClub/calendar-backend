# frozen_string_literal: true

module Preferences
  # Renders the title, description and location templates of resolved
  # preferences (Preferences::Resolver) with the variables of a
  # Preferences::Context. The sync and the ICS feed (Applier), the schedule
  # JSON (MeetingTimeSerializer) and the settings previews all render through
  # #text, so each shows what the calendar shows.
  class Preview
    TEXT_TEMPLATES = { summary: :title_template, description: :description_template, location: :location_template }.freeze

    # One template rendered for one record, after the strict check. Raises
    # TemplateRenderer::InvalidTemplateError.
    def self.render_template(template, record)
      TemplateRenderer.validate_template(template)
      TemplateRenderer.new.render(template, Context.for(record).variables)
    end

    # One renderer serves many events, so a template that many events share is
    # parsed once.
    def initialize(renderer = TemplateRenderer.new)
      @renderer = renderer
    end

    # The summary, description and location that the templates give. A field
    # with no template is left out, so the event keeps its own value.
    def text(preferences, variables)
      TEXT_TEMPLATES.each_with_object({}) do |(field, template_field), text|
        template = preferences[template_field]
        next if template.blank?

        rendered = @renderer.render(template, variables)
        # A blank variable, such as a placeholder building, leaves a space at an end.
        text[field] = field == :location ? rendered.strip : rendered
      end
    end

    # The text with the variable's value where no template is set.
    def call(preferences, variables)
      text = text(preferences, variables)
      {
        title:       text[:summary] || variables[:title],
        description: text[:description] || "",
        location:    text[:location] || variables[:location] || ""
      }
    end
  end
end
