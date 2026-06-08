# frozen_string_literal: true

# Broadcasts real-time events to clients via ActionCable (solid_cable in production).
# Replaces the Redis pub/sub approach from the previous backend.
class SseBroadcaster
  CHANNEL = "SseEventsChannel"

  class << self
    def publish(type, data = {}, user_id: nil)
      event = {
        type:      type,
        data:      data,
        timestamp: Time.current.iso8601,
        user_id:   user_id
      }.compact

      stream = user_id ? "sse_events_user_#{user_id}" : "sse_events"
      ActionCable.server.broadcast(stream, event)
      Rails.logger.info("SSE: Published event #{type} to #{stream}")
    end

    def broadcast_enrollment(action, enrollment, user_id: nil)
      publish(
        "enrollment.#{action}",
        {
          id:        enrollment.id,
          user_id:   enrollment.user_id,
          course_id: enrollment.course_id
        },
        user_id: user_id
      )
    end

    def broadcast_model_event(model, action)
      publish(
        "#{model.model_name.param_key}.#{action}",
        {
          id:      model.id,
          type:    model.class.name,
          changes: model.previous_changes.except("updated_at")
        }
      )
    end
  end
end
