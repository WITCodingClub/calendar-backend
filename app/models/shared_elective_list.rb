# frozen_string_literal: true

# An elective list that the catalog defines once for every program, on its
# policy pages: the HSS lists, the English sequence, co-op, and free
# electives. Each one is an ElectiveGroup with this name in a requirement set,
# with no plan. DegreeRequirements::SharedElectives makes them at import, and
# degree progress fills a slot of one by its kind, never by its display name.
#
# kind: :hss, :humanities, :social_science, :english, :co_op, :free, or
# :directed_hss (an HSS slot that names its course, "HSS Elective
# (PSYC4552)"). courses are course keys.
SharedElectiveList = Data.define(:kind, :name, :heading, :subject_codes, :courses, :any_course)

class SharedElectiveList
  HUMANITIES = %w[CSAS HIST HSSI HUMN LITR PHIL].freeze
  SOCIAL_SCIENCES = %w[COMM CSAS ECON ENVM HSSI POLS PSYC SOCL].freeze
  # Every course of the four English sequences. A slot takes one course.
  ENGLISH_SEQUENCE = [ [ "ENGL", 700 ], [ "ENGL", 800 ], [ "ENGL", 900 ], [ "ENGL", 1100 ], [ "ENGL", 2200 ] ].freeze
  # A co-op semester is a work term. COOP2500 (Introduction to Cooperative
  # Education) is a course row of its own, required before the first term,
  # so it does not meet a co-op semester. Nor does COOP3000 (optional co-op)
  # or COOP6500 (graduate).
  CO_OP_SUBJECT = "COOP"
  CO_OP_TERMS = [ [ CO_OP_SUBJECT, 3500 ], [ CO_OP_SUBJECT, 4500 ], [ CO_OP_SUBJECT, 5000 ] ].freeze

  HSS = new(kind: :hss, name: "HSS Electives", heading: "Humanities or social science elective",
            subject_codes: (HUMANITIES + SOCIAL_SCIENCES).uniq.sort, courses: [], any_course: false)
  HUMANITIES_LIST = new(kind: :humanities, name: "Humanities Electives", heading: "Humanities elective",
                        subject_codes: HUMANITIES, courses: [], any_course: false)
  SOCIAL_SCIENCES_LIST = new(kind: :social_science, name: "Social Science Electives", heading: "Social science elective",
                             subject_codes: SOCIAL_SCIENCES, courses: [], any_course: false)
  ENGLISH = new(kind: :english, name: "English Sequence", heading: "One course of the student's English sequence",
                subject_codes: [], courses: ENGLISH_SEQUENCE, any_course: false)
  CO_OP = new(kind: :co_op, name: "Co-op", heading: "Co-op semester",
              subject_codes: [], courses: CO_OP_TERMS, any_course: false)
  FREE = new(kind: :free, name: "Free Electives", heading: "Free or general elective",
             subject_codes: [], courses: [], any_course: true)

  BY_NAME = [ HSS, HUMANITIES_LIST, SOCIAL_SCIENCES_LIST, ENGLISH, CO_OP, FREE ].index_by(&:name).freeze
  HSS_KINDS = %i[hss humanities social_science directed_hss].freeze
  DIRECTED_NAME = "HSS Elective ("

  # The directed HSS elective of one course, such as "HSS Elective (PSYC4552)".
  def self.directed(key, heading)
    new(kind: :directed_hss, name: "#{DIRECTED_NAME}#{key.join})", heading: heading,
        subject_codes: [], courses: [ key ], any_course: false)
  end

  # The kind of a list by its name, or nil for a list of the program's own
  # page.
  def self.kind_of(name)
    return nil if name.nil?

    BY_NAME[name]&.kind || (:directed_hss if name.start_with?(DIRECTED_NAME))
  end

  # true for the list of an HSS slot.
  def self.hss?(name) = HSS_KINDS.include?(kind_of(name))
end
