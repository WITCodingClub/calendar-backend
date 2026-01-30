# frozen_string_literal: true

# Service to build processed events data for a user's schedule.
# Used by both UsersController and FriendsController to avoid duplication.
class ProcessedEventsBuilder
  include ApplicationHelper

  def initialize(user, term)
    @user = user
    @term = term
    @preference_resolver = PreferenceResolver.new(user)
    @template_renderer = CalendarTemplateRenderer.new
  end

  def build
    # Preload user's calendar preferences to avoid N+1 queries
    @user.calendar_preferences.load
    @user.event_preferences.load

    enrollments = @user
                  .enrollments
                  .where(term_id: @term.id)
                  .includes(course: [
                              :faculties,
                              { meeting_times: [:event_preference, { room: :building }, { course: :faculties }] }
                            ])

    structured_data = enrollments.map do |enrollment|
      build_course_data(enrollment)
    end

    {
      classes: structured_data,
      notifications_disabled: @user.notifications_disabled?
    }
  end

  private

  def build_course_data(enrollment)
    course = enrollment.course
    faculty = course.faculties.first

    # Filter meeting times to prefer valid locations over TBD duplicates
    filtered_meeting_times = filter_meeting_times(course.meeting_times)

    {
      title: titleize_with_roman_numerals(course.title),
      course_number: course.course_number,
      schedule_type: course.schedule_type,
      prefix: course.prefix,
      term: {
        pub_id: @term.public_id,
        uid: @term.uid,
        season: @term.season,
        year: @term.year
      },
      professor: build_professor_data(faculty),
      meeting_times: build_meeting_times_data(filtered_meeting_times)
    }
  end

  def build_professor_data(faculty)
    return nil unless faculty

    {
      pub_id: faculty.public_id,
      first_name: faculty.first_name,
      last_name: faculty.last_name,
      email: faculty.email,
      rmp_id: faculty.rmp_id
    }
  end

  def filter_meeting_times(meeting_times)
    meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                 .map do |_key, group|
                   # If multiple meeting times exist for same day/time, prefer non-TBD over TBD
                   non_tbd = group.reject { |mt| tbd_location?(mt) }
                   non_tbd.any? ? non_tbd.first : group.first
                 end
  end

  def tbd_location?(meeting_time)
    LocationHelper.tbd_location?(meeting_time.building, meeting_time.room)
  end

  def build_meeting_times_data(meeting_times)
    meeting_times.map do |mt|
      days = build_days_hash(mt.day_of_week)
      preferences = @preference_resolver.resolve_actual_for(mt)
      context = CalendarTemplateRenderer.build_context_from_meeting_time(mt)

      rendered_title = render_title(preferences, context, mt)
      rendered_description = render_description(preferences, context)

      color_value = preferences[:color_id] || mt.event_color
      witcc_color = GoogleColors.to_witcc_hex(color_value)

      {
        id: mt.public_id,
        begin_time: mt.fmt_begin_time_military,
        end_time: mt.fmt_end_time_military,
        start_date: mt.start_date,
        end_date: mt.end_date,
        location: build_location_data(mt),
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
  end

  def build_days_hash(day_of_week)
    days = {
      monday: false,
      tuesday: false,
      wednesday: false,
      thursday: false,
      friday: false,
      saturday: false,
      sunday: false
    }

    day_symbol = day_of_week&.to_sym
    days[day_symbol] = true if day_symbol
    days
  end

  def build_location_data(meeting_time)
    {
      building: if meeting_time.building
                  {
                    pub_id: meeting_time.building.public_id,
                    name: meeting_time.building.name,
                    abbreviation: meeting_time.building.abbreviation
                  }
                else
                  nil
                end,
      room: meeting_time.room&.formatted_number
    }
  end

  def render_title(preferences, context, meeting_time)
    if preferences[:title_template].present?
      @template_renderer.render(preferences[:title_template], context)
    else
      titleize_with_roman_numerals(meeting_time.course.title)
    end
  end

  def render_description(preferences, context)
    return nil if preferences[:description_template].blank?

    @template_renderer.render(preferences[:description_template], context)
  end

end
