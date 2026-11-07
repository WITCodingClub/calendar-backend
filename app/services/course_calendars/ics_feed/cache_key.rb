# frozen_string_literal: true

require "digest"

module CourseCalendars
  class IcsFeed
    # The Rails.cache key for a user's rendered feed (#680). Calendar apps poll
    # the feed many times for each change, so the key comes from the rows the
    # feed reads, and a change to any of them gives a new key.
    #
    # One query reads a fingerprint of each table. For the user's own rows
    # (courses, meeting times, preferences, friend meetings), the fingerprint is
    # the id and updated_at of each row, so an insert, an update, or a delete
    # changes it. The finals of the user's terms, the university events, and all
    # rooms and buildings are many rows, so they use the count and the latest
    # updated_at.
    #
    # The key also holds the date (the feed drops past finals), the deploy
    # revision (a code change can change the body), and the user row.
    #
    # A write that skips updated_at (update_all, update_columns) does not move
    # the key. TTL limits how long such a feed stays in the cache. The same
    # write also leaves LAST-MODIFIED in the feed as it was, so calendar apps
    # keep their old copy too.
    #
    # When you make the feed read a new table or column, add it here. Increase
    # VERSION to drop every cached feed.
    class CacheKey
      VERSION = 1
      TTL     = 1.day

      def initialize(user, today: Time.zone.today)
        @user  = user
        @today = today
      end

      def to_s
        "ics_feed/v#{VERSION}/#{@user.id}/#{digest}"
      end

      private

      def digest
        inputs = {
          user: [ @user.id, @user.updated_at&.iso8601(6), @user.notifications_disabled? ],
          today: @today.iso8601,
          revision: VersionService.current_sha,
          # The holidays come from their own cache entry, which can lag the
          # table by up to its TTL. Its value goes in the key, so a feed built
          # from an old entry is not kept after that entry is refreshed.
          no_class_spans: Digest::SHA256.hexdigest(UniversityCalendarEvent.cached_no_class_spans.to_json),
          rows: fingerprints
        }

        Digest::SHA256.hexdigest(JSON.generate(inputs))
      end

      # One query with a scalar subquery for each table.
      def fingerprints
        columns = parts.map { |name, sql| Arel::Nodes::Grouping.new(Arel.sql(sql)).as(name.to_s) }
        ActiveRecord::Base.connection.select_one(Arel::SelectManager.new.project(*columns), "IcsFeed::CacheKey")
      end

      def parts # rubocop:disable Metrics/AbcSize
        course_ids        = Enrollment.where(user_id: @user.id).select(:course_id)
        term_ids          = Course.where(id: course_ids).select(:term_id)
        meeting_time_ids  = Course::MeetingTime.where(course_id: course_ids).select(:id)
        meeting_time_rooms = Course::MeetingTimeRoom.where(meeting_time_id: meeting_time_ids)
        course_faculties  = CourseFaculty.where(course_id: course_ids)
        friend_meetings   = FriendMeeting.where(user_id: @user.id)
        attendees         = FriendMeetingAttendee.where(friend_meeting_id: friend_meetings.select(:id))

        {
          enrollments: rows(Enrollment.where(user_id: @user.id)),
          courses: rows(Course.where(id: course_ids)),
          terms: rows(Term.where(id: term_ids)),
          meeting_times: rows(Course::MeetingTime.where(id: meeting_time_ids)),
          meeting_time_rooms: rows(meeting_time_rooms),
          # All rooms and buildings: a final's LOCATION names any room that its
          # location text matches, not only the rooms of the user's classes.
          rooms: summary(Room.all),
          buildings: summary(Building.all),
          # courses_faculties has no timestamps: its columns are the data.
          course_faculties: rows(course_faculties, :faculty_id, :primary_indicator, timestamps: false),
          faculties: rows(Faculty.where(id: course_faculties.select(:faculty_id))),
          # RecurrenceEnd reads the finals week of each term from every final in it.
          final_exams: summary(FinalExam.where(term_id: term_ids).or(FinalExam.where(course_id: course_ids))),
          # Holidays, finals periods, and the categories the user syncs.
          university_events: summary(UniversityCalendarEvent.all),
          extension_config: rows(UserExtensionConfig.where(user_id: @user.id)),
          event_preferences: rows(EventPreference.where(user_id: @user.id)),
          calendar_preferences: rows(CalendarPreference.where(user_id: @user.id)),
          friend_meetings: rows(friend_meetings),
          # not_ended depends on the time, not only on the rows.
          live_friend_meetings: rows(friend_meetings.live.not_ended, timestamps: false),
          friend_meeting_publications: rows(FriendMeetingPublication.where(friend_meeting_id: friend_meetings.select(:id))),
          friend_meeting_attendees: rows(attendees),
          attendee_users: summary(User.where(id: attendees.select(:user_id)))
        }
      end

      # An md5 of the id, the given columns, and updated_at of each row, in id
      # order. An insert, an update, or a delete changes it.
      def rows(relation, *columns, timestamps: true)
        table  = relation.klass.quoted_table_name
        fields = [ :id, *columns ]
        fields << :updated_at if timestamps
        values = fields.map { |field| "#{table}.#{relation.klass.connection.quote_column_name(field)}" }

        relation.unscope(:order, :select).select(Arel.sql(
          "md5(coalesce(string_agg(concat_ws(':', #{values.join(', ')}), ',' ORDER BY #{table}.\"id\"), ''))"
        )).to_sql
      end

      # The count and the latest updated_at. An insert or an update moves the
      # time, and a delete lowers the count.
      def summary(relation)
        table = relation.klass.quoted_table_name

        relation.unscope(:order, :select).select(Arel.sql(
          "concat_ws(':', count(*), max(#{table}.\"updated_at\"))"
        )).to_sql
      end
    end
  end
end
