# frozen_string_literal: true

# The public ids of EncodedIds, such as "usr_k5x9q2": the model's prefix, the
# separator, and a hashid. An id with the separator is a public id. Clients
# also send database ids, so every lookup that takes both reads the rule here.
module PublicIds
  module_function

  def separator = EncodedIds.configuration.separator

  def public_id?(id) = id.to_s.include?(separator)

  # The record of scope (a model or a relation) with the public id or the
  # database id, or nil.
  def find(scope, id)
    return nil if id.blank?

    public_id?(id) ? scope.find_by_public_id(id.to_s) : scope.find_by(id: id)
  end

  def find!(scope, id)
    find(scope, id) || raise(ActiveRecord::RecordNotFound.new(nil, scope.name))
  end

  # The database id in a public id of model, with no query. Nil when id is
  # not a public id with the model's prefix.
  def decode(model, id)
    return nil unless public_id?(id)

    prefix, _, hash = id.to_s.rpartition(separator)
    model.decode_id(hash) if prefix == model.get_public_id_prefix && hash.present?
  end

  # A bare hashid as a public id of model. A public id stays as it is.
  def with_prefix(model, id)
    public_id?(id) ? id.to_s : "#{model.get_public_id_prefix}#{separator}#{id}"
  end
end
