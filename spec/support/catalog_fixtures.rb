# frozen_string_literal: true

# A small but realistic catalog: two terms, four sections, two instructors, and
# meeting times chosen so the day and time filters have something to bite on.
#
#   COMP 1000-01  Mon 09:00-10:15, Fri 09:00-10:15   Ada Byron   (rated)
#   COMP 2000-01  Tue 13:00-14:15                    Grace Hop   (unrated)
#   COMP 2000-02  Fri 16:00-17:15                    Ada Byron
#   MATH 1750-01  Mon 11:00-12:15  (spring term)
RSpec.shared_context "catalog fixtures" do
  let!(:fall_term)   { Term.create!(uid: 202710, year: 2026, season: :fall) }
  let!(:spring_term) { Term.create!(uid: 202620, year: 2026, season: :spring) }

  let!(:building) { Building.create!(abbreviation: "ANNX", name: "Test Annex") }
  let!(:room)     { Room.create!(building: building, number: "306") }

  let!(:ada) do
    Faculty.create!(first_name: "Ada", last_name: "Byron", email: "byrona@wit.edu",
                    title: "Professor", school: "School of Computing & Data Science",
                    rmp_id: "rmp-ada")
  end

  let!(:grace) do
    Faculty.create!(first_name: "Grace", last_name: "Hop", email: "hopg@wit.edu")
  end

  # Ada has real ratings; Grace has none, so the sentinel handling is covered.
  let!(:ada_ratings) do
    RatingDistribution.create!(faculty: ada, avg_rating: 4.5, avg_difficulty: 2.5,
                               num_ratings: 12, would_take_again_percent: 88.0)
  end

  let!(:grace_ratings) do
    RatingDistribution.create!(faculty: grace, avg_rating: 0, avg_difficulty: 0,
                               num_ratings: 0, would_take_again_percent: -1)
  end

  let!(:comp1000) { build_section(crn: 10_001, number: 1000, section: "01", faculty: ada) }
  let!(:comp2000) { build_section(crn: 10_002, number: 2000, section: "01", faculty: grace) }
  let!(:comp2000b) { build_section(crn: 10_003, number: 2000, section: "02", faculty: ada) }

  let!(:math1750) do
    build_section(crn: 20_001, number: 1750, section: "01", subject: "Mathematics (MATH)",
                  term: spring_term)
  end

  let!(:cancelled_section) do
    build_section(crn: 10_999, number: 3000, section: "01").tap do |course|
      course.update!(status: :cancelled)
    end
  end

  let!(:comp1000_final) do
    FinalExam.create!(term: fall_term, course: comp1000, crn: comp1000.crn,
                      exam_date: Date.new(2026, 12, 17), start_time: 800, end_time: 1000,
                      location: "ANNX 306")
  end

  before do
    add_meeting(comp1000, :monday, 900, 1015, room: room)
    add_meeting(comp1000, :friday, 900, 1015)
    add_meeting(comp2000, :tuesday, 1300, 1415)
    add_meeting(comp2000b, :friday, 1600, 1715)
    add_meeting(math1750, :monday, 1100, 1215)
    add_meeting(cancelled_section, :monday, 800, 915)
  end

  def build_section(crn:, number:, section:, subject: "Computer Science (COMP)",
                    term: fall_term, faculty: nil, credit_hours: 4)
    course = term.courses.create!(
      crn: crn, subject: subject, course_number: number, section_number: section,
      title: "Course #{number}", schedule_type: :lecture, credit_hours: credit_hours,
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
    )
    course.faculties << faculty if faculty
    course
  end

  def add_meeting(course, day, begin_time, end_time, room: nil)
    meeting = course.meeting_times.create!(
      day_of_week: day, begin_time: begin_time, end_time: end_time,
      meeting_schedule_type: :lecture, meeting_type: :class_meeting,
      start_date: course.start_date, end_date: course.end_date
    )
    meeting.rooms << room if room
    meeting
  end
end
