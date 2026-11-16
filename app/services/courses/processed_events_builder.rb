# frozen_string_literal: true

module Courses
  # One person's classes with their meeting times (MeetingTimeSerializer),
  # for a friend's schedule, the course history, and the MCP course tools.
  class ProcessedEventsBuilder
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
        meeting_times: build_meeting_times_data(course.filtered_meeting_times)
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

    def build_meeting_times_data(meeting_times)
      meeting_times.map do |meeting_time|
        MeetingTimeSerializer.new(meeting_time, preference_resolver: @preference_resolver,
                                                template_renderer: @template_renderer, recurrence: @recurrence).as_json
      end
    end
  end
end
