# frozen_string_literal: true

module Types
  class SectionType < BaseObject
    description "One course section, identified by its CRN within a term"

    connection_type_class Types::BaseConnection

    field :crn, Integer, null: false
    field :pub_id, String, null: false, method: :public_id
    field :term, TermType, null: false
    field :subject, String, null: false, description: "e.g. \"Computer Science (COMP)\""
    field :subject_code, String, null: false, description: "e.g. \"COMP\"", method: :prefix
    field :course_number, Integer, null: false
    field :section_number, String, null: false
    field :course_code, String, null: false, description: "e.g. \"COMP 2000-01\""
    field :title, String, null: false
    field :schedule_type, ScheduleTypeEnum, null: false
    field :schedule_type_code, String, null: false, description: "Banner code, e.g. \"LEC\""
    field :credit_hours, Integer, null: true
    field :grade_mode, String, null: true
    field :status, String, null: false
    field :seats, SeatsType, null: false
    field :linked, LinkedSectionsType, null: false
    field :start_date, GraphQL::Types::ISO8601Date, null: false
    field :end_date, GraphQL::Types::ISO8601Date, null: false
    field :instructors, [ InstructorType ], null: false, method: :faculties
    field :meeting_times, [ MeetingTimeType ], null: false
    field :final_exam, FinalExamType, null: true

    def course_code
      ::Catalog::SectionSerializer.course_code_for(object)
    end

    def schedule_type_code
      Course::ScheduleType.new(object.schedule_type).code
    end

    def seats
      { capacity: object.seats_capacity, available: object.seats_available }
    end

    def linked
      partners = object.linked_sections.pluck(:crn, :id)

      {
        required:   object.is_section_linked,
        identifier: object.link_identifier,
        crns:       partners.map(&:first),
        pub_ids:    partners.map { |(_crn, id)| Course.public_id_for(id) }
      }
    end

    # filtered_meeting_times drops the duplicate rows a concurrent ingest can
    # leave behind, preferring the copy that has a real room.
    def meeting_times
      object.filtered_meeting_times
            .sort_by { |mt| [ Course::MeetingTime.day_of_weeks[mt.day_of_week], mt.begin_time ] }
    end
  end
end
