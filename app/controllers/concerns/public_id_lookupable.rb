# frozen_string_literal: true

module PublicIdLookupable
  extend ActiveSupport::Concern

  def find_by_any_id(model_class, id)
    return nil if id.blank?

    if id.to_s.include?("_")
      model_class.find_by_public_id(id)
    else
      model_class.find_by(id: id)
    end
  end

  def find_by_any_id!(model_class, id)
    result = find_by_any_id(model_class, id)
    raise ActiveRecord::RecordNotFound.new(nil, model_class.name) if result.nil?

    result
  end
end
