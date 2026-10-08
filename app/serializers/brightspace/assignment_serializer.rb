# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_assignments
#
#  id                 :bigint           not null, primary key
#  closes_at          :datetime
#  description        :text
#  due_at             :datetime
#  feedback           :text
#  kind               :string           not null
#  opens_at           :datetime
#  removed_at         :datetime
#  source_url         :string
#  submission_status  :string
#  submitted_at       :datetime
#  title              :string           not null
#  user_due_at        :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_assignments_on_course_offering_id  (course_offering_id)
#  index_brightspace_assignments_on_source              (course_offering_id,kind,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
module Brightspace
  # One assignment. The list form leaves out the long text fields.
  class AssignmentSerializer
    def initialize(assignment, detail: false)
      @assignment = assignment
      @detail     = detail
    end

    def as_json(*)
      json = {
        id:                @assignment.public_id,
        class_id:          @assignment.course_offering.public_id,
        source_id:         @assignment.source_id,
        kind:              @assignment.kind,
        title:             @assignment.title,
        source_url:        @assignment.source_url,
        due_at:            iso(@assignment.due_at),
        opens_at:          iso(@assignment.opens_at),
        closes_at:         iso(@assignment.closes_at),
        user_due_at:       iso(@assignment.user_due_at),
        effective_due_at:  iso(@assignment.effective_due_at),
        submission_status: @assignment.submission_status,
        submitted_at:      iso(@assignment.submitted_at),
        removed_at:        iso(@assignment.removed_at),
        preference:        AssignmentPreferenceSerializer.new(@assignment.preference).as_json
      }
      return json unless @detail

      json.merge(
        description:      @assignment.description,
        feedback:         @assignment.feedback,
        deadline_changes: @assignment.deadline_changes.order(detected_at: :desc, id: :desc).limit(20).map do |change|
          {
            field:       change.field,
            previous_at: iso(change.previous_at),
            current_at:  iso(change.current_at),
            detected_at: iso(change.detected_at)
          }
        end
      )
    end

    private

    def iso(time) = time&.utc&.iso8601
  end
end
