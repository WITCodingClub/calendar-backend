# frozen_string_literal: true

# The Brightspace account that the extension saw for a user. A user has at
# most one active connection. A disconnected one keeps its data, and linking
# the same host and learner again reuses it.
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
  class Connection < ApplicationRecord
    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :bsc, min_hash_length: 12

    STATUSES = %w[active disconnected].freeze

    belongs_to :user
    has_many :syncs, class_name: "Brightspace::Sync", dependent: :destroy, inverse_of: :connection
    has_many :course_offerings, class_name: "Brightspace::CourseOffering", dependent: :destroy, inverse_of: :connection

    normalizes :host, with: ->(host) { host.to_s.strip.downcase.delete_prefix("https://").delete_prefix("http://").delete_suffix("/") }
    normalizes :learner_id, with: ->(id) { id.to_s.strip }

    validates :host, presence: true, length: { maximum: 255 },
                     format: { with: /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/, message: "must be a host name" }
    validates :learner_id, presence: true, length: { maximum: 64 }
    validates :learner_id, uniqueness: { scope: [ :user_id, :host ] }
    validates :status, inclusion: { in: STATUSES }
    validates :connected_at, presence: true

    scope :active, -> { where(status: "active") }

    def active?       = status == "active"
    def disconnected? = status == "disconnected"

    # The connection whose data the read routes show: the active one, or the
    # one disconnected last when none is active.
    def self.current_for(user)
      where(user: user).order(Arel.sql("CASE WHEN status = 'active' THEN 0 ELSE 1 END"), connected_at: :desc).first
    end

    # Links the account. A different account deactivates the old one, because
    # a user has one active connection. The same account comes back with its
    # old records.
    def self.link!(user:, host:, learner_id:)
      transaction do
        user.lock!
        connection = where(user: user).find_or_initialize_by(host: normalize_value_for(:host, host),
                                                             learner_id: normalize_value_for(:learner_id, learner_id))
        where(user: user, status: "active").where.not(id: connection.id).find_each(&:disconnect!)

        unless connection.persisted? && connection.active?
          connection.assign_attributes(status: "active", connected_at: Time.current, disconnected_at: nil)
        end
        connection.reconnect_required_at = nil
        connection.save!
        connection
      end
    end

    def matches?(host:, learner_id:)
      self.host == self.class.normalize_value_for(:host, host) &&
        self.learner_id == self.class.normalize_value_for(:learner_id, learner_id)
    end

    def disconnect!
      update!(status: "disconnected", disconnected_at: Time.current)
    end
  end
end
