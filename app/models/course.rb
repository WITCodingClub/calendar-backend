# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
#
#  id                    :bigint           not null, primary key
#  banner_synced_at      :datetime
#  campus                :string
#  course_number         :integer          not null
#  credit_hours          :integer
#  crn                   :integer          not null
#  cross_list_available  :integer
#  cross_list_capacity   :integer
#  cross_list_identifier :string
#  end_date              :date             not null
#  grade_mode            :string
#  is_section_linked     :boolean          default(FALSE), not null
#  link_identifier       :string
#  links_fetched_at      :datetime
#  part_of_term          :string
#  schedule_type         :string           not null
#  seats_available       :integer
#  seats_capacity        :integer
#  section_number        :string           not null
#  start_date            :date             not null
#  status                :string           default("active"), not null
#  subject               :string           not null
#  title                 :string           not null
#  waitlist_available    :integer
#  waitlist_capacity     :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  term_id               :bigint           not null
#
# Indexes
#
#  index_courses_on_course_and_link_identifier  (term_id,subject,course_number,link_identifier)
#  index_courses_on_course_number_text_trgm     (((course_number)::text) gin_trgm_ops) USING gin
#  index_courses_on_crn_and_term_id             (crn,term_id) UNIQUE
#  index_courses_on_status                      (status)
#  index_courses_on_subject_trgm                (subject gin_trgm_ops) USING gin
#  index_courses_on_title_trgm                  (title gin_trgm_ops) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class Course < ApplicationRecord
  include CourseChangeTrackable
  include EncodedIds::HashidIdentifiable

  tracks_calendar_changes "title", "start_date", "end_date", "subject", "course_number", "section_number", course_id: :id, on: :update

  # CourseCode.subject_of in SQL: the subject code of each section.
  SUBJECT_CODE_SQL = <<~'SQL'.squish
    UPPER(BTRIM(COALESCE(SUBSTRING(courses.subject FROM '\(([A-Z0-9]{2,6})\)\s*$'), courses.subject)))
  SQL

  # Joins each section to its CatalogCourse by the subject code and number.
  CATALOG_COURSE_JOIN = <<~SQL.squish
    INNER JOIN catalog_courses
      ON catalog_courses.course_number = courses.course_number
     AND catalog_courses.subject_code = #{SUBJECT_CODE_SQL}
  SQL

  set_public_id_prefix :crs

  def to_param
    public_id
  end

  belongs_to :term

  # Banner's lecture and lab pairs for this section (Catalog::SectionLinksSync).
  has_many :section_links, dependent: :delete_all
  has_many :banner_linked_courses, through: :section_links, source: :linked_course
  # Ordered on the join so `faculties.first` is Banner's primary instructor and
  # not whichever join row happens to be oldest.
  has_many :course_faculties, -> { in_banner_order }, dependent: :destroy, inverse_of: :course
  has_many :faculties, through: :course_faculties
  has_many :meeting_times, class_name: "Course::MeetingTime", dependent: :destroy
  has_many :meeting_time_rooms, class_name: "Course::MeetingTimeRoom", through: :meeting_times
  has_many :rooms, through: :meeting_time_rooms
  has_many :enrollments, dependent: :destroy
  has_many :users, through: :enrollments
  has_one :final_exam, dependent: :destroy

  normalizes :title, with: Courses::TitleFormatter.method(:call)

  validates :crn, uniqueness: { scope: :term_id, message: "has already been taken for this term" }, allow_nil: true

  after_destroy :update_term_dates
  after_save :update_term_dates, if: -> { saved_change_to_start_date? || saved_change_to_end_date? }

  scope :joins_catalog_course, -> { joins(CATALOG_COURSE_JOIN) }
  # Sections that Banner has not confirmed since the time (banner_synced_at).
  scope :banner_synced_before, ->(time) { where(banner_synced_at: nil).or(where(banner_synced_at: ...time)) }

  enum :status, { active: "active", cancelled: "cancelled" }
  enum :schedule_type, Course::ScheduleType::TYPES.transform_values { |v| v[:code] }

  def schedule_type_description
    return nil unless schedule_type

    Course::ScheduleType.new(schedule_type).readable_description
  end

  def prefix
    CourseCode.subject_of(subject)
  end

  # The public id is derived from the numeric id, not stored, so a list of them
  # is built rather than plucked.
  def self.public_id_for(id)
    "#{get_public_id_prefix}#{EncodedIds.configuration.separator}#{encode_id(id)}"
  end

  # Turns "crs_kw7coe30" back into the numeric id. Returns nil when the prefix
  # or the hash does not belong to a course.
  def self.id_from_public_id(value)
    separator = EncodedIds.configuration.separator
    parts     = value.to_s.strip.split(separator)
    hash      = parts.pop
    return nil unless parts.join(separator) == get_public_id_prefix

    decode_id(hash)
  end

  # Banner writes linked sections as <slot><key>. The slot says what the section
  # is for within the pairing, and the key says which pairing it belongs to. In
  # CHEM 1000 the lecture "A1" goes with the labs "B1", and the lecture "A2"
  # with the labs "B2".
  def link_slot
    link_identifier&.first
  end

  def link_key
    link_identifier.presence && link_identifier[1..].presence
  end

  # The CRNs of the other sections in this section's cross-list group: sections
  # of different courses that meet together (Catalog::Importer). A list of
  # sections reads the groups of a term with one query in each request.
  def cross_listed_crns
    return [] if cross_list_identifier.nil?

    groups = Current.cross_lists[term_id] ||=
      Course.active.where(term_id: term_id).where.not(cross_list_identifier: nil)
            .order(:crn).pluck(:cross_list_identifier, :crn)
            .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    Array(groups[cross_list_identifier]) - [ crn ]
  end

  # Sections a student has to register alongside this one: same course, same
  # link key, a different slot. Returns none when the section is not linked.
  def linked_sections
    return Course.none if link_key.blank?

    Course.active
          .where(term_id: term_id, subject: subject, course_number: course_number)
          .where("SUBSTRING(link_identifier FROM 2) = ?", link_key)
          .where.not(id: id)
          .where.not(link_identifier: nil)
          .where("LEFT(link_identifier, 1) <> ?", link_slot)
  end

  # linked_sections for one section in memory: the same rule, with no query.
  # Catalog::SectionLinks uses it for sections that are already loaded.
  def link_partner?(other)
    return false if link_key.blank? || other.id == id || other.link_identifier.nil?

    other.active? && other.term_id == term_id && other.subject == subject &&
      other.course_number == course_number && other.link_key == link_key && other.link_slot != link_slot
  end

  # The ids of the sections in `scope` whose course is closest to the vector,
  # nearest course first and by CRN within a course. Catalog::SemanticSearch
  # calls it.
  #
  # The vector belongs to the course, so the search ranks the courses that
  # have a section in `scope`, and the scope's filters, such as the term, run
  # before the cut.
  #
  # @param vector [Array<Float>]
  # @param scope [ActiveRecord::Relation<Course>]
  # @param limit [Integer] the most sections to return. A search with no term
  #   can find many sections for each course, so the list is cut here too.
  # @return [Array<Integer>]
  def self.ids_nearest_to(vector, scope:, limit:)
    catalog_ids = CatalogCourse.nearest_ids(vector, limit: limit, among: catalog_course_ids_in(scope))
    ids_in_catalog_order(scope, catalog_ids).first(limit)
  end

  def self.catalog_course_ids_in(scope)
    scope.unscope(:order, :select).joins_catalog_course.select("catalog_courses.id")
  end

  # The ids of the sections in `scope` whose course is one of `catalog_ids`,
  # in that order, and by CRN within a course. A CRN is unique only within a
  # term, so the id breaks a tie, and every page of a search sees one order.
  def self.ids_in_catalog_order(scope, catalog_ids)
    return [] if catalog_ids.empty?

    rank = catalog_ids.each_with_index.to_h
    scope.unscope(:order, :select).joins_catalog_course
         .where(catalog_courses: { id: catalog_ids })
         .pluck(:id, "catalog_courses.id", :crn)
         .uniq
         .sort_by { |id, catalog_id, crn| [ rank.fetch(catalog_id), crn, id ] }
         .map(&:first)
  end

  # The CatalogCourse of this section. Catalog::CourseDetailsSync.seed makes
  # one for every course that has a section.
  def catalog_course
    CatalogCourse.find_by(subject_code: prefix, course_number: course_number)
  end

  # Sections that teach something close to this one, nearest first.
  #
  # Same term, because a student picks from what is offered now. The other
  # sections of this same course are left out: they carry the same words, so
  # they would fill the list with what the student is already looking at.
  def similar_sections(limit: Embeddable::DEFAULT_SIMILAR_LIMIT)
    course = catalog_course
    return Course.none if course&.embedding.nil?

    offered = Course.active.where(term_id: term_id)
    catalog_ids = CatalogCourse.nearest_ids(course.embedding, limit: limit,
                                                              among: Course.catalog_course_ids_in(offered),
                                                              except: course.id)
    ids = Course.ids_in_catalog_order(offered, catalog_ids).first(limit)

    Course.where(id: ids).in_order_of(:id, ids)
  end

  # One meeting time for each day and hours. A concurrent ingest can save a
  # TBD row next to the real one; the first row with a real room wins.
  def filtered_meeting_times
    mts = meeting_times.loaded? ? meeting_times : meeting_times.includes(rooms: :building)
    mts.group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
       .map do |_key, group|
         next group.first if group.size == 1

         group.find { |mt| !mt.tbd_location? } || group.first
       end
  end

  private

  def update_term_dates
    term.course_dates_changed!
  end
end
