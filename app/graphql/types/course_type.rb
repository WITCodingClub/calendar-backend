# frozen_string_literal: true

module Types
  class CourseType < BaseObject
    description "One course, such as COMP 2350, across terms, with Banner's description and prerequisites"

    connection_type_class Types::BaseConnection
    edge_type_class Types::BaseEdge

    field :code, String, null: false, description: "e.g. \"COMP 2350\""
    field :subject_code, String, null: false
    field :course_number, Integer, null: false
    field :title, String, null: true
    field :description, String, null: true
    field :credit_hours, Integer, null: true
    field :typically_offered, [ String ], null: false, description: "fall, spring, or summer"
    field :prerequisites, GraphQL::Types::JSON, null: true,
          description: "An and/or tree of courses and placement tests. Each course has its code, title, and linked."
    field :corequisites, GraphQL::Types::JSON, null: false
    field :restrictions, GraphQL::Types::JSON, null: false
    field :mutual_exclusions, GraphQL::Types::JSON, null: false,
          description: "Courses that block this one once a student completes one of them. Each has its code, title, and linked."
    field :college, String, null: true
    field :division, String, null: true, description: "e.g. \"COF Eligible Cross Reg\" for a course open to Colleges of the Fenway students"
    field :department, String, null: true
    field :levels, [ String ], null: false, description: "e.g. Undergraduate, Graduate"
    field :grading_modes, [ String ], null: false, description: "e.g. Standard Letter, Pass/Fail"
    field :fees, [ FeeType ], null: false
    field :learning_objectives, String, null: true, description: "From Banner's syllabus page, one objective or line on each line"
    field :unlocks, [ CourseType ], null: false, complexity: 5, description: "Courses that list this one as a prerequisite"

    # The same shapes as GET /api/v1/catalog/courses/:code.
    def prerequisites     = serialized[:prerequisites]
    def corequisites      = serialized[:corequisites]
    def mutual_exclusions = serialized[:mutual_exclusions]
    def unlocks           = object.unlocks.order(:subject_code, :course_number).distinct

    private

    def serialized
      @serialized ||= ::Catalog::CourseSerializer.new(object).as_json
    end
  end
end
