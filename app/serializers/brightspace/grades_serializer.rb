# frozen_string_literal: true

module Brightspace
  # The gradebook of one class as Brightspace reports it, with the user's
  # grade settings and scenarios next to it. Points and weights are numbers
  # or null. A null is unknown, never zero.
  class GradesSerializer
    def initialize(offering)
      @offering = offering
    end

    def as_json(*)
      {
        reported_total: @offering.reported_total,
        categories:     categories.map { |category| category_json(category) },
        items:          items.map { |item| item_json(item) },
        preferences:    ClassPreferenceSerializer.new(@offering.preference).as_json[:grades],
        scenarios:      @offering.grade_scenarios.order(:created_at, :id).map { |scenario| GradeScenarioSerializer.new(scenario).as_json },
        version:        @offering.version
      }
    end

    private

    def categories
      @offering.grade_categories.not_removed.order(:id)
    end

    def items
      @offering.grade_items.not_removed.includes(:grade_category, :assignment).order(:id)
    end

    def category_json(category)
      {
        id:           category.public_id,
        source_id:    category.source_id,
        name:         category.name,
        weight:       number(category.weight),
        drop_lowest:  category.drop_lowest,
        drop_highest: category.drop_highest,
        extra_credit: category.extra_credit
      }
    end

    def item_json(item)
      {
        id:              item.public_id,
        source_id:       item.source_id,
        category_id:     item.grade_category&.public_id,
        assignment_id:   item.assignment&.public_id,
        name:            item.name,
        points_earned:   number(item.points_earned),
        points_possible: number(item.points_possible),
        weight:          number(item.weight),
        grading_status:  item.grading_status,
        extra_credit:    item.extra_credit,
        feedback:        item.feedback,
        graded_at:       item.graded_at&.utc&.iso8601
      }
    end

    def number(value) = value&.to_f
  end
end
