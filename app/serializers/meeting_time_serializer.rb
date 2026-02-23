# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id    (course_id)
#  index_meeting_times_on_day_of_week  (day_of_week)
#  index_meeting_times_on_room_id      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
class MeetingTimeSerializer
  include ApplicationHelper

  # @param meeting_time [MeetingTime]
  # @param preference_resolver [PreferenceResolver] shared resolver instance across a collection
  # @param template_renderer [CalendarTemplateRenderer] shared renderer instance across a collection
  def initialize(meeting_time, preference_resolver:, template_renderer:)
    @mt = meeting_time
    @preference_resolver = preference_resolver
    @template_renderer = template_renderer
  end

  def as_json(*)
    preferences = @preference_resolver.resolve_actual_for(@mt)
    context = CalendarTemplateRenderer.build_context_from_meeting_time(@mt)

    rendered_title = if preferences[:title_template].present?
                       @template_renderer.render(preferences[:title_template], context)
                     else
                       titleize_with_roman_numerals(@mt.course.title)
                     end

    rendered_description = if preferences[:description_template].present?
                             @template_renderer.render(preferences[:description_template], context)
                           end

    color_value = preferences[:color_id] || @mt.event_color
    witcc_color = GoogleColors.to_witcc_hex(color_value)

    {
      id: @mt.public_id,
      begin_time: @mt.fmt_begin_time_military,
      end_time: @mt.fmt_end_time_military,
      start_date: @mt.start_date,
      end_date: @mt.end_date,
      location: {
        building: building_json,
        room: @mt.room&.formatted_number
      },
      **days,
      calendar_config: {
        title: rendered_title,
        description: rendered_description,
        color_id: witcc_color,
        reminder_settings: preferences[:reminder_settings],
        visibility: preferences[:visibility]
      }
    }
  end

  private

  def days
    result = {
      monday: false,
      tuesday: false,
      wednesday: false,
      thursday: false,
      friday: false,
      saturday: false,
      sunday: false
    }
    day_symbol = @mt.day_of_week&.to_sym
    result[day_symbol] = true if day_symbol
    result
  end

  def building_json
    return nil unless @mt.building

    {
      pub_id: @mt.building.public_id,
      name: @mt.building.name,
      abbreviation: @mt.building.abbreviation
    }
  end

end
