# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_connections
#
#  id                    :bigint           not null, primary key
#  connected_at          :datetime         not null
#  disconnected_at       :datetime
#  host                  :string           not null
#  last_synced_at        :datetime
#  reconnect_required_at :datetime
#  status                :string           default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  learner_id            :string           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_brightspace_connections_on_identity          (user_id,host,learner_id) UNIQUE
#  index_brightspace_connections_on_user_id           (user_id)
#  index_brightspace_connections_one_active_per_user  (user_id) UNIQUE WHERE ((status)::text = 'active'::text)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  class ConnectionSerializer
    def initialize(connection)
      @connection = connection
    end

    def as_json(*)
      return nil if @connection.nil?

      {
        id:                    @connection.public_id,
        host:                  @connection.host,
        learner_id:            @connection.learner_id,
        status:                @connection.status,
        reconnect_required:    @connection.reconnect_required_at.present?,
        connected_at:          @connection.connected_at&.utc&.iso8601,
        disconnected_at:       @connection.disconnected_at&.utc&.iso8601,
        last_synced_at:        @connection.last_synced_at&.utc&.iso8601,
        reconnect_required_at: @connection.reconnect_required_at&.utc&.iso8601
      }
    end
  end
end
