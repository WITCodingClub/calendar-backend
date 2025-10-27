class SseBroadcaster
  CHANNEL = "sse_events".freeze

  class << self
    # Broadcast an event to all SSE clients
    #
    # @param type [String] Event type (e.g., "course_event.created", "enrollment.updated")
    # @param data [Hash] Event payload data
    # @param user_id [Integer, nil] Optional user_id to target specific users
    #
    # Example:
    #   SseBroadcaster.publish("course_event.created", { id: 123, title: "Math 101" })
    def publish(type, data = {}, user_id: nil)
      event = {
        type: type,
        data: data,
        timestamp: Time.current.iso8601,
        user_id: user_id
      }.compact

      redis.publish(CHANNEL, event.to_json)
      Rails.logger.info("SSE: Published event #{type} to #{CHANNEL}")
    end

    # Broadcast a course event
    def broadcast_course_event(action, course_event)
      publish(
        "course_event.#{action}",
        {
          id: course_event.id,
          academic_class: {
            id: course_event.academic_class.id,
            title: course_event.academic_class.title,
            course_code: course_event.academic_class.course_code
          },
          start_time: course_event.start_time,
          end_time: course_event.end_time,
          location: course_event.location
        }
      )
    end

    # Broadcast an enrollment event
    def broadcast_enrollment(action, enrollment, user_id: nil)
      publish(
        "enrollment.#{action}",
        {
          id: enrollment.id,
          user_id: enrollment.user_id,
          academic_class_id: enrollment.academic_class_id
        },
        user_id: user_id
      )
    end

    # Broadcast a generic model event
    def broadcast_model_event(model, action)
      publish(
        "#{model.model_name.param_key}.#{action}",
        {
          id: model.id,
          type: model.class.name,
          changes: model.previous_changes.except("updated_at")
        }
      )
    end

    private

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end
  end
end
