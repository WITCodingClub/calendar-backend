# frozen_string_literal: true

# Graded work in a class: an assignment (dropbox), a quiz, or a discussion.
# The class-wide dates and this student's own state are separate columns, so
# an individual deadline never hides the class deadline.
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
  class Assignment < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::Removable

    set_public_id_prefix :bas, min_hash_length: 12

    KINDS = %w[assignment quiz discussion].freeze
    SUBMISSION_STATUSES = %w[not_submitted submitted graded exempt].freeze

    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :assignments
    has_many :grade_items, class_name: "Brightspace::GradeItem", dependent: :nullify, inverse_of: :assignment
    has_one :preference, class_name: "Brightspace::AssignmentPreference", dependent: :destroy, inverse_of: :assignment
    has_many :deadline_changes, class_name: "Brightspace::DeadlineChange", dependent: :destroy, inverse_of: :assignment
    # The sync deletes the remote event of a removed assignment. A row that
    # stays without its assignment is an orphan for the cleanup job.
    has_many :calendar_events, foreign_key: :brightspace_assignment_id, dependent: :nullify, inverse_of: :brightspace_assignment

    validates :kind, inclusion: { in: KINDS }
    validates :source_id, presence: true, length: { maximum: 64 },
                          uniqueness: { scope: [ :course_offering_id, :kind ] }
    validates :title, presence: true, length: { maximum: 500 }
    validates :submission_status, inclusion: { in: SUBMISSION_STATUSES }, allow_nil: true

    # SQL for the effective deadline. It needs a LEFT JOIN of the preferences
    # (see .with_preferences).
    EFFECTIVE_DUE_AT_SQL = "COALESCE(brightspace_assignment_preferences.due_at_override, " \
                           "brightspace_assignments.user_due_at, brightspace_assignments.due_at)"

    scope :with_preferences, -> { left_joins(:preference) }
    scope :by_effective_due_at, lambda {
      with_preferences.order(Arel.sql("#{EFFECTIVE_DUE_AT_SQL} ASC NULLS LAST"), :id)
    }

    # The deadline that applies to this student before any personal override.
    def brightspace_due_at
      user_due_at || due_at
    end

    # A personal override first, then the individual Brightspace deadline,
    # then the class deadline.
    def effective_due_at
      preference&.due_at_override || brightspace_due_at
    end

    def progress
      preference&.progress || "not_started"
    end

    # Brightspace confirms that the work is in, or the user marked it done.
    # Reminders for pending work stop then.
    def finished?
      %w[submitted graded exempt].include?(submission_status) || progress == "done"
    end
  end
end
