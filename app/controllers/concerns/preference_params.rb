# frozen_string_literal: true

# Shared strong-parameter helpers for calendar/event preference controllers.
# Included by both Api:: and Dashboard:: preference controllers so JSON and
# form paths stay in lockstep (color hex↔id, reminder normalization).
module PreferenceParams
  extend ActiveSupport::Concern

  private

  def calendar_preference_params
    permitted = params.require(:calendar_preference).permit(
      :title_template, :description_template, :location_template,
      :color_id, :visibility, reminder_settings: []
    )

    if params[:calendar_preference][:reminder_settings].present?
      permitted[:reminder_settings] = params[:calendar_preference][:reminder_settings].map do |reminder|
        reminder.permit(:time, :method, :type)
      end
    elsif params[:calendar_preference].key?(:reminder_settings)
      permitted[:reminder_settings] = []
    end

    if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
      permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
    end

    permitted
  end

  def event_preference_params
    permitted = params.require(:event_preference).permit(
      :title_template, :description_template, :location_template,
      :color_id, :visibility, reminder_settings: []
    )

    if params[:event_preference][:reminder_settings].present?
      permitted[:reminder_settings] = params[:event_preference][:reminder_settings].map do |r|
        r.permit(:time, :method, :type)
      end
    elsif params[:event_preference].key?(:reminder_settings)
      permitted[:reminder_settings] = []
    end

    if permitted[:color_id].is_a?(String) && permitted[:color_id].start_with?("#")
      permitted[:color_id] = GoogleColors.witcc_to_color_id(permitted[:color_id])
    end

    permitted
  end

  def generate_preview(resolved_preferences, context)
    renderer    = CalendarTemplateRenderer.new
    title       = resolved_preferences[:title_template].present? ? renderer.render(resolved_preferences[:title_template], context) : context[:title]
    description = resolved_preferences[:description_template].present? ? renderer.render(resolved_preferences[:description_template], context) : ""
    location    = resolved_preferences[:location_template].present? ? renderer.render(resolved_preferences[:location_template], context) : (context[:location] || "")
    { title: title, description: description, location: location }
  end
end
