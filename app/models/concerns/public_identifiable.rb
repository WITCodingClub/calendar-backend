# frozen_string_literal: true

# Stripe-like public IDs that don't require adding a column to the database.
# Usage:
#   class User < ApplicationRecord
#     include PublicIdentifiable
#     set_public_id_prefix :usr
#   end
#
#   # For tables with many records, use a longer hashid:
#   class Enrollment < ApplicationRecord
#     include PublicIdentifiable
#     set_public_id_prefix :enr, min_hash_length: 12
#   end
#
#   user = User.first
#   user.public_id # => "usr_h1izp"
#   User.find_by_public_id("usr_h1izp") # => #<User id: 1>
#
module PublicIdentifiable
  extend ActiveSupport::Concern

  included do
    include Hashid::Rails

    class_attribute :public_id_prefix
    class_attribute :hashid_min_length, default: 8
  end

  def public_id
    "#{self.public_id_prefix}_#{hashid}"
  end

  module ClassMethods
    def set_public_id_prefix(prefix, min_hash_length: 8)
      self.public_id_prefix = prefix.to_s.downcase
      self.hashid_min_length = min_hash_length

      # Configure hashid-rails for this model with custom length
      hashid_config(min_hash_length: min_hash_length)
    end

    def find_by_public_id(id)
      return nil unless id.is_a? String

      prefix = id.split("_").first.to_s.downcase
      hash = id.split("_").last
      return nil unless prefix == get_public_id_prefix

      find_by_hashid(hash)
    end

    def find_by_public_id!(id)
      obj = find_by_public_id(id)
      raise ActiveRecord::RecordNotFound.new(nil, name) if obj.nil?

      obj
    end

    def get_public_id_prefix
      return public_id_prefix.to_s.downcase if public_id_prefix.present?

      raise NotImplementedError, "The #{name} model includes PublicIdentifiable module, but set_public_id_prefix hasn't been called."
    end
  end
end
