# frozen_string_literal: true

module Brightspace
  # The grading-rule format that class preferences and grade scenarios share:
  #
  #   [{ "category_id" => "bgc_...", "name" => "Labs", "weight" => 40,
  #      "drop_lowest" => 1, "drop_highest" => nil, "extra_credit" => false,
  #      "item_ids" => ["bgi_..."] }]
  #
  # category_id names an imported category, or is nil for a category that the
  # user made. item_ids maps grade items into the category. Every id must
  # belong to the same class.
  module GradeRules
    KEYS = %w[category_id name weight drop_lowest drop_highest extra_credit item_ids].freeze
    MAX_CATEGORIES = 100

    # Returns the list of error messages for rules of the given class.
    def self.errors_for(rules, course_offering)
      return [] if rules.nil?
      return [ "must be a list" ] unless rules.is_a?(Array)
      return [ "has more than #{MAX_CATEGORIES} categories" ] if rules.size > MAX_CATEGORIES

      category_ids = course_offering ? course_offering.grade_categories.map(&:public_id).to_set : Set.new
      item_ids     = course_offering ? course_offering.grade_items.map(&:public_id).to_set : Set.new

      rules.each_with_index.flat_map do |rule, index|
        next [ "item #{index} must be an object" ] unless rule.is_a?(Hash)

        rule_errors(rule.stringify_keys, category_ids, item_ids).map { |message| "item #{index} #{message}" }
      end
    end

    def self.rule_errors(rule, category_ids, item_ids)
      errors = []
      unknown = rule.keys - KEYS
      errors << "has an unknown key: #{unknown.first}" if unknown.any?
      errors << "needs a name or a category_id" if rule["name"].blank? && rule["category_id"].blank?
      errors << "name must be a string of at most 200 characters" unless rule["name"].nil? || (rule["name"].is_a?(String) && rule["name"].length <= 200)
      errors << "category_id is not a category of this class" if rule["category_id"].present? && !category_ids.include?(rule["category_id"])
      errors << "weight must be a number of 0 or more" unless rule["weight"].nil? || (rule["weight"].is_a?(Numeric) && rule["weight"] >= 0)
      %w[drop_lowest drop_highest].each do |key|
        errors << "#{key} must be a whole number of 0 or more" unless rule[key].nil? || (rule[key].is_a?(Integer) && rule[key] >= 0)
      end
      errors << "extra_credit must be true or false" unless [ nil, true, false ].include?(rule["extra_credit"])

      ids = rule["item_ids"]
      if !ids.nil? && !(ids.is_a?(Array) && ids.all?(String))
        errors << "item_ids must be a list of grade item ids"
      elsif ids.present? && !ids.all? { |id| item_ids.include?(id) }
        errors << "item_ids has an id that is not a grade item of this class"
      end

      errors
    end
  end
end
