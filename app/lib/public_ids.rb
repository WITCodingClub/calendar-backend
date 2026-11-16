# frozen_string_literal: true

# The public ids of EncodedIds, such as "usr_k5x9q2": the model's prefix, the
# separator, and a hashid. An id with the separator is a public id. Clients
# also send a bare hashid or a database id, so every lookup that takes them
# reads the rule here.
module PublicIds
  module_function

  def separator = EncodedIds.configuration.separator

  def public_id?(id) = id.to_s.include?(separator)

  # The record of scope (a model or a relation) with the public id, the bare
  # hashid, or the database id (record_id), or nil.
  def find(scope, id)
    record_id = record_id(scope.respond_to?(:klass) ? scope.klass : scope, id)
    record_id && scope.find_by(id: record_id)
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

  # The database id in id, with no query: a public id of model, a bare
  # hashid, or a string of digits. Nil for anything else. A hashid that
  # starts with digits ("12abcdef") must never be read as the number 12.
  def record_id(model, id)
    return nil if id.blank?
    return decode(model, id) if public_id?(id)

    model.decode_id(id.to_s) || Integer(id.to_s, 10, exception: false)
  end

  # A bare hashid as a public id of model. A public id stays as it is.
  def with_prefix(model, id)
    public_id?(id) ? id.to_s : "#{model.get_public_id_prefix}#{separator}#{id}"
  end
end
