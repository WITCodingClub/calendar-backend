# frozen_string_literal: true

module Api
  # Finds a record by its public id ("usr_...") or its database id. +scope+ is
  # a model class or a relation, so current_user.passkeys finds only the
  # user's own rows and another user's id answers 404.
  module PublicIdLookupable
    extend ActiveSupport::Concern

    private

    def find_by_any_id(scope, id)
      return nil if id.blank?

      if id.to_s.include?("_")
        scope.find_by_public_id(id)
      else
        scope.find_by(id: id)
      end
    end

    def find_by_any_id!(scope, id)
      find_by_any_id(scope, id) || raise(ActiveRecord::RecordNotFound.new(nil, scope.name))
    end
  end
end
