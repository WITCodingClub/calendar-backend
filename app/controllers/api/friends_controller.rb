# frozen_string_literal: true

module Api
  class FriendsController < ApiController
    include ApplicationHelper

    # GET /api/friends
    # Returns accepted friends: { friends: [{ id: string, name: string }] }
    def index
      authorize :friendship, :index?

      friends = current_user.friends.map do |friend|
        {
          id: friend.public_id,
          name: friend.full_name
        }
      end

      render json: { friends: friends }, status: :ok
    end

    # GET /api/friends/requests
    # Returns { incoming: [...], outgoing: [...] }
    def requests
      authorize :friendship, :requests?

      incoming = current_user.incoming_friend_requests.includes(:requester).map do |fr|
        {
          request_id: fr.public_id,
          from: {
            id: fr.requester.public_id,
            name: fr.requester.full_name
          },
          created_at: fr.created_at.iso8601
        }
      end

      outgoing = current_user.outgoing_friend_requests.includes(:addressee).map do |fr|
        {
          request_id: fr.public_id,
          to: {
            id: fr.addressee.public_id,
            name: fr.addressee.full_name
          },
          created_at: fr.created_at.iso8601
        }
      end

      render json: { incoming: incoming, outgoing: outgoing }, status: :ok
    end

    # POST /api/friends/requests
    # Create request with { friend_id: string }
    def create_request
      friend_user = find_by_any_id!(User, params[:friend_id])

      friendship = Friendship.new(
        requester: current_user,
        addressee: friend_user
      )

      authorize friendship, :create?

      friendship.save!

      render json: { request_id: friendship.public_id }, status: :created
    end

    # POST /api/friends/requests/:request_id/accept
    def accept
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :accept?

      friendship.accepted!

      friend = friendship.friend_for(current_user)

      render json: {
        friendship_id: friendship.public_id,
        friend: {
          id: friend.public_id,
          name: friend.full_name
        }
      }, status: :ok
    end

    # POST /api/friends/requests/:request_id/decline
    def decline
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :decline?

      friendship.destroy!

      render json: { ok: true }, status: :ok
    end

    # DELETE /api/friends/requests/:request_id
    # Cancel outgoing request
    def cancel_request
      friendship = find_by_any_id!(Friendship, params[:request_id])
      authorize friendship, :cancel?

      friendship.destroy!

      render json: { ok: true }, status: :ok
    end

    # DELETE /api/friends/:friend_id
    # Unfriend
    def unfriend
      friend_user = find_by_any_id!(User, params[:friend_id])

      friendship = Friendship.accepted
                             .where("(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
                                    current_user.id, friend_user.id, friend_user.id, current_user.id)
                             .first

      if friendship.nil?
        render json: { error: "Friendship not found" }, status: :not_found
        return
      end

      authorize friendship, :destroy?

      friendship.destroy!

      render json: { ok: true }, status: :ok
    end

    # POST /api/friends/:friend_id/processed_events
    # Get friend's schedule (same format as /user/processed_events)
    def processed_events
      friend_user = find_by_any_id!(User, params[:friend_id])

      # Find the accepted friendship
      friendship = find_friendship_with(friend_user)

      if friendship.nil?
        render json: { error: "You are not friends with this user" }, status: :forbidden
        return
      end

      authorize friendship, :view_schedule?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      result = build_processed_events_for_user(friend_user, term)

      render json: result, status: :ok
    end

    # POST /api/friends/:friend_id/is_processed
    # Check if friend has courses for term
    def is_processed
      friend_user = find_by_any_id!(User, params[:friend_id])

      # Find the accepted friendship
      friendship = find_friendship_with(friend_user)

      if friendship.nil?
        render json: { error: "You are not friends with this user" }, status: :forbidden
        return
      end

      authorize friendship, :view_schedule?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      processed = friend_user.enrollments.exists?(term_id: term.id)

      render json: { processed: processed }, status: :ok
    end

    private

    def find_friendship_with(friend_user)
      Friendship.accepted
                .where("(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
                       current_user.id, friend_user.id, friend_user.id, current_user.id)
                .first
    end

    def build_processed_events_for_user(user, term)
      # Preload user's calendar preferences
      user.calendar_preferences.load
      user.event_preferences.load

      enrollments = user
                    .enrollments
                    .where(term_id: term.id)
                    .includes(course: [
                                :faculties,
                                { meeting_times: [:event_preference, { room: :building }, { course: :faculties }] }
                              ])

      structured_data = enrollments.map do |enrollment|
        course = enrollment.course
        faculty = course.faculties.first

        # Filter meeting times to prefer valid locations over TBD duplicates
        filtered_meeting_times = filter_meeting_times_for_user(user, course.meeting_times)

        {
          title: titleize_with_roman_numerals(course.title),
          course_number: course.course_number,
          schedule_type: course.schedule_type,
          prefix: course.prefix,
          term: {
            pub_id: term.public_id,
            uid: term.uid,
            season: term.season,
            year: term.year
          },
          professor: if faculty
                       {
                         pub_id: faculty.public_id,
                         first_name: faculty.first_name,
                         last_name: faculty.last_name,
                         email: faculty.email,
                         rmp_id: faculty.rmp_id
                       }
                     else
                       nil
                     end,
          meeting_times: group_meeting_times_for_user(user, filtered_meeting_times)
        }
      end

      {
        classes: structured_data,
        notifications_disabled: user.notifications_disabled?
      }
    end

    def filter_meeting_times_for_user(user, meeting_times)
      meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                   .map do |_key, group|
                     non_tbd = group.reject { |mt| tbd_location?(user, mt) }
                     non_tbd.any? ? non_tbd.first : group.first
                   end
    end

    def tbd_location?(user, meeting_time)
      (meeting_time.building && user.send(:tbd_building?, meeting_time.building)) ||
        (meeting_time.room && user.send(:tbd_room?, meeting_time.room))
    end

    def group_meeting_times_for_user(user, meeting_times)
      preference_resolver = PreferenceResolver.new(user)
      template_renderer = CalendarTemplateRenderer.new

      meeting_times.map do |mt|
        days = {
          monday: false,
          tuesday: false,
          wednesday: false,
          thursday: false,
          friday: false,
          saturday: false,
          sunday: false
        }

        day_symbol = mt.day_of_week&.to_sym
        days[day_symbol] = true if day_symbol

        preferences = preference_resolver.resolve_actual_for(mt)
        context = CalendarTemplateRenderer.build_context_from_meeting_time(mt)

        rendered_title = if preferences[:title_template].present?
                           template_renderer.render(preferences[:title_template], context)
                         else
                           titleize_with_roman_numerals(mt.course.title)
                         end

        rendered_description = if preferences[:description_template].present?
                                 template_renderer.render(preferences[:description_template], context)
                               end

        color_value = preferences[:color_id] || mt.event_color
        witcc_color = GoogleColors.to_witcc_hex(color_value)

        {
          id: mt.public_id,
          begin_time: mt.fmt_begin_time_military,
          end_time: mt.fmt_end_time_military,
          start_date: mt.start_date,
          end_date: mt.end_date,
          location: {
            building: if mt.building
                        {
                          pub_id: mt.building.public_id,
                          name: mt.building.name,
                          abbreviation: mt.building.abbreviation
                        }
                      else
                        nil
                      end,
            room: mt.room&.formatted_number
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
    end

  end
end
