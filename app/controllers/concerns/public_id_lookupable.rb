# frozen_string_literal: true

# Provides helper methods for looking up records by either internal ID or public_id.
# This allows API endpoints to accept both formats for backwards compatibility.
#
# Usage:
#   include PublicIdLookupable
#
#   # Find or return nil
#   record = find_by_any_id(User, params[:user_id])
#
#   # Find or raise RecordNotFound
#   record = find_by_any_id!(MeetingTime, params[:meeting_time_id])
#
module PublicIdLookupable
  extend ActiveSupport::Concern

  # Find a record by either internal ID or public_id
  # @param model_class [Class] The ActiveRecord model class
  # @param id [String, Integer] The ID to look up (internal or public_id)
  # @return [ActiveRecord::Base, nil] The found record or nil
  def find_by_any_id(model_class, id)
    return nil if id.blank?

    # If it contains an underscore, it's likely a public_id (e.g., "usr_abc123")
    if id.to_s.include?("_")
      model_class.find_by_public_id(id)
    else
      # Fall back to internal ID lookup
      model_class.find_by(id: id)
    end
  end

  # Find a record by either internal ID or public_id, raising if not found
  # @param model_class [Class] The ActiveRecord model class
  # @param id [String, Integer] The ID to look up (internal or public_id)
  # @return [ActiveRecord::Base] The found record
  # @raise [ActiveRecord::RecordNotFound] If no record is found
  def find_by_any_id!(model_class, id)
    result = find_by_any_id(model_class, id)
    raise ActiveRecord::RecordNotFound.new(nil, model_class.name) if result.nil?

    result
  end
end
