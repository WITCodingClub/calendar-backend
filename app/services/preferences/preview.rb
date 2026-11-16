# frozen_string_literal: true

module Preferences
  # The title, description and location that a calendar event gets from the
  # resolved preferences (Preferences::Resolver) and the variables of its
  # Preferences::Context. A field with no template keeps the variable's value.
  class Preview
    # One template rendered for one record, after the strict check. Raises
    # TemplateRenderer::InvalidTemplateError.
    def self.render_template(template, record)
      TemplateRenderer.validate_template(template)
      TemplateRenderer.new.render(template, Context.for(record).variables)
    end

    # One preview renders many events with one renderer, so a template that
    # many events share is parsed once.
    def initialize
      @renderer = TemplateRenderer.new
    end

    def call(preferences, context)
      {
        title:       render(preferences[:title_template], context) || context[:title],
        description: render(preferences[:description_template], context) || "",
        location:    render(preferences[:location_template], context) || context[:location] || ""
      }
    end

    private

    def render(template, context)
      @renderer.render(template, context) if template.present?
    end
  end
end
