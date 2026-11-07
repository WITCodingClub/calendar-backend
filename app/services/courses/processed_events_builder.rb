# frozen_string_literal: true

module Courses
  class Courses::ProcessedEventsBuilder
    ENROLLMENT_INCLUDES = [
      :term,
      { course: [
        :faculties,
        { meeting_times: [ :event_preference, { rooms: :building }, { course: [ :faculties, :term ] } ] }
      ] }
    ].freeze

    # The result of build for each user in one term, keyed by user id. The
    # number of queries does not grow with the number of users (#681):
    # enrollments, preferences, and the recurrence lookups load once for all.
    def self.build_for_users(users, term)
      return {} if users.empty?

      user_ids    = users.map(&:id)
      enrollments = Enrollment.where(user_id: user_ids, term_id: term.id).includes(ENROLLMENT_INCLUDES).to_a
      ActiveRecord::Associations::Preloader.new(records: users, associations: :user_extension_config).call
      event_preferences    = EventPreference.where(user_id: user_ids).group_by(&:user_id)
      calendar_preferences = CalendarPreference.where(user_id: user_ids).group_by(&:user_id)
      recurrences          = CourseCalendars::RecurrenceBuilder.preloaded_for_users(users, enrollments.map(&:course))
      enrollments_by_user  = enrollments.group_by(&:user_id)

      users.to_h do |user|
        resolver = Preferences::Resolver.new(user,
                                             event_preferences: event_preferences.fetch(user.id, []),
                                             calendar_preferences: calendar_preferences.fetch(user.id, []))
        builder = new(user, term, preference_resolver: resolver)
        [ user.id, builder.build_from(enrollments_by_user.fetch(user.id, []), recurrences.fetch(user.id)) ]
      end
    end

    # term is needed only for build. classes_by_term takes its own terms.
    def initialize(user, term = nil, preference_resolver: nil)
      @user = user
      @term = term
      @preference_resolver = preference_resolver || Preferences::Resolver.new(user)
      @template_renderer = Preferences::TemplateRenderer.new(user_id: user.id)
    end

    def build
      {
        classes: classes_by_term([ @term ]).fetch(@term.id, []),
        notifications_disabled: @user.notifications_disabled?
      }
    end

    # The same result as build, from enrollments and a recurrence builder that
    # the caller loaded. build_for_users uses it.
    def build_from(enrollments, recurrence)
      {
        classes: build_classes(enrollments, recurrence),
        notifications_disabled: @user.notifications_disabled?
      }
    end

    # The user's classes in each of the terms, keyed by term id, from one
    # enrollments query. A term with no classes has no key.
    def classes_by_term(terms)
      @user.calendar_preferences.load
      @user.event_preferences.load

      enrollments = @user.enrollments.where(term_id: terms.map(&:id)).includes(ENROLLMENT_INCLUDES)
      recurrence  = CourseCalendars::RecurrenceBuilder.preloaded(@user, enrollments.map(&:course))

      enrollments.group_by(&:term_id).transform_values do |term_enrollments|
        build_classes(term_enrollments, recurrence)
      end
    end

    private

    def build_classes(enrollments, recurrence)
      @recurrence = recurrence
      enrollments.map { |enrollment| build_course_data(enrollment) }
    end

    def build_course_data(enrollment)
      course = enrollment.course
      faculty = course.faculties.first

      filtered_meeting_times = filter_meeting_times(course.meeting_times)

      {
        title: course.title,
        crn: course.crn,
        course_number: course.course_number,
        schedule_type: course.schedule_type,
        prefix: course.prefix,
        term: {
          pub_id: enrollment.term.public_id,
          uid: enrollment.term.uid,
          season: enrollment.term.season,
          year: enrollment.term.year
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
      meeting_times.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
                   .map do |_key, group|
                     non_tbd = group.reject { |mt| tbd_location?(mt) }
                     non_tbd.any? ? non_tbd.first : group.first
                   end
    end

    def tbd_location?(meeting_time)
      LocationHelper.tbd_building?(meeting_time.building) ||
        meeting_time.rooms.all? { |r| LocationHelper.tbd_room?(r) }
    end

    def build_meeting_times_data(meeting_times)
      meeting_times.map do |mt|
        days = build_days_hash(mt.day_of_week)
        preferences = @preference_resolver.resolve_actual_for(mt)
        context = Preferences::TemplateRenderer.build_context_from_meeting_time(mt)

        rendered_title = render_title(preferences, context, mt)
        rendered_description = render_description(preferences, context)

        {
          id: mt.public_id,
          begin_time: mt.fmt_begin_time_military,
          end_time: mt.fmt_end_time_military,
          start_date: mt.start_date,
          end_date: mt.end_date,
          effective_end_date: @recurrence.effective_end_date(mt).iso8601,
          excluded_dates: @recurrence.excluded_dates(mt).map(&:iso8601),
          location: build_location_data(mt),
          **days,
          calendar_config: {
            title: rendered_title,
            description: rendered_description,
            color_id: GoogleCalendar::Colors.normalize(preferences[:color_id]) || mt.event_color,
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
      building = meeting_time.building
      {
        building: if building
                    {
                      pub_id: building.public_id,
                      name: building.name,
                      abbreviation: building.abbreviation
                    }
                  else
                    nil
                  end,
        rooms: meeting_time.rooms.map(&:formatted_number)
      }
    end

    def render_title(preferences, context, meeting_time)
      if preferences[:title_template].present?
        @template_renderer.render(preferences[:title_template], context)
      else
        meeting_time.course.title
      end
    end

    def render_description(preferences, context)
      return nil if preferences[:description_template].blank?

      @template_renderer.render(preferences[:description_template], context)
    end
  end
end
