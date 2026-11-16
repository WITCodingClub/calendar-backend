# frozen_string_literal: true

module Api
  # Finds a record by its public id ("usr_...") or its database id (PublicIds). +scope+ is
  # a model class or a relation, so current_user.passkeys finds only the
  # user's own rows and another user's id answers 404.
  module PublicIdLookupable
    extend ActiveSupport::Concern

    private

    def find_by_any_id(scope, id) = PublicIds.find(scope, id)

    def find_by_any_id!(scope, id) = PublicIds.find!(scope, id)
  end
end
