# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ScheduleOptions::Finder do
  let(:term) { create(:term, uid: 202720, season: :spring, year: 2027) }

  def section(crn, code, schedule_type: "LEC", credit_hours: 4, **attributes)
    subject_code, number = code.split
    create(:catalog_course, subject_code: subject_code, course_number: number.to_i) unless CatalogCourse.exists?(subject_code: subject_code, course_number: number.to_i)
    create(:course, term: term, crn: crn, subject: "Subject (#{subject_code})", course_number: number.to_i,
                    schedule_type: schedule_type, credit_hours: credit_hours, **attributes)
  end

  def meets(course, days, from, to, **attributes)
    Array(days).each do |day|
      create(:course_meeting_time, course: course, day_of_week: day, begin_time: from, end_time: to, **attributes)
    end
    course
  end

  # A Banner pair: the lecture needs the lab, and the lab needs the lecture.
  def pair(lecture, lab, group: 0)
    [ lecture, lab ].each { |course| course.update!(is_section_linked: true, links_fetched_at: Time.current) }
    create(:section_link, course: lecture, linked_course: lab, option_group: group, credit_hours: 0)
    create(:section_link, course: lab, linked_course: lecture, option_group: 0, credit_hours: 4)
  end

  def find(courses, preferences: nil, limit: nil)
    described_class.new({ term_uid: term.uid, courses: courses, preferences: preferences, limit: limit }.compact).call
  end

  def count(courses, preferences: nil)
    described_class.new({ term_uid: term.uid, courses: courses, preferences: preferences }.compact).count
  end

  def crn_sets(result) = result[:schedules].map { |schedule| schedule[:crns] }

  describe "lecture and lab pairs" do
    it "puts each lecture with its own Banner lab, even when another lab would fit" do
      lecture = meets(section(20410, "COMP 3350"), %i[monday wednesday], 1000, 1115)
      pair(lecture, meets(section(20411, "COMP 3350", schedule_type: "LAB", credit_hours: nil), :tuesday, 1300, 1450))
      other_lab = meets(section(20412, "COMP 3350", schedule_type: "LAB", credit_hours: nil), :thursday, 1300, 1450)
      pair(section(20413, "COMP 3350", status: :cancelled), other_lab)

      result = find([ { codes: [ "COMP 3350" ] } ])

      expect(crn_sets(result)).to eq([ %w[20410 20411] ])
      expect(result[:schedules].first[:courses]).to eq([ { code: "COMP 3350", crns: %w[20410 20411] } ])
      expect(result[:schedules].first[:totals]).to include(credit_hours: 4, days: %w[monday tuesday wednesday])
    end

    it "gives one schedule for each option group of a lecture" do
      lecture = meets(section(20410, "COMP 3350"), :monday, 1000, 1115)
      pair(lecture, meets(section(20411, "COMP 3350", schedule_type: "LAB"), :tuesday, 1300, 1450), group: 0)
      lab_two = meets(section(20412, "COMP 3350", schedule_type: "LAB"), :thursday, 1300, 1450)
      create(:section_link, course: lecture, linked_course: lab_two, option_group: 1, credit_hours: 0)
      lab_two.update!(is_section_linked: true, links_fetched_at: Time.current)
      create(:section_link, course: lab_two, linked_course: lecture, credit_hours: 4)

      expect(crn_sets(find([ { codes: [ "COMP 3350" ] } ]))).to eq([ %w[20410 20411], %w[20410 20412] ])
    end

    it "pairs by the link identifiers before Banner's pairs are stored" do
      section(20410, "COMP 3350", is_section_linked: true, link_identifier: "A1")
      section(20411, "COMP 3350", schedule_type: "LAB", is_section_linked: true, link_identifier: "B1")
      section(20412, "COMP 3350", schedule_type: "LAB", is_section_linked: true, link_identifier: "B2")

      expect(crn_sets(find([ { codes: [ "COMP 3350" ] } ]))).to eq([ %w[20410 20411] ])
    end

    it "never returns a linked section whose partner is cancelled" do
      lecture = section(20410, "COMP 3350")
      pair(lecture, section(20411, "COMP 3350", schedule_type: "LAB", status: :cancelled))

      result = find([ { codes: [ "COMP 3350" ] } ])

      expect(result[:count]).to eq(0)
      expect(result[:not_offered]).to be_empty
    end

    it "does not let a lab alone stand for a course that has a lecture" do
      section(20410, "COMP 1100")
      section(21202, "COMP 1100", schedule_type: "LAB", is_section_linked: true, links_fetched_at: Time.current)

      expect(crn_sets(find([ { codes: [ "COMP 1100" ] } ]))).to eq([ %w[20410] ])
    end

    it "loads a partner of another course code through the link" do
      lecture = meets(section(20410, "PHYS 1250"), :monday, 1000, 1115)
      lab     = meets(section(20900, "PHYS 1251", schedule_type: "LAB"), :tuesday, 1000, 1150)
      pair(lecture, lab)

      result = find([ { codes: [ "PHYS 1250" ] } ])

      expect(crn_sets(result)).to eq([ %w[20410 20900] ])
      expect(result[:schedules].first[:totals][:days]).to eq(%w[monday tuesday])
    end
  end

  describe "a lecture and a lab of different codes" do
    let!(:lecture) { meets(section(20410, "PHYS 1250"), :monday, 1000, 1115) }
    let!(:lab) { meets(section(20900, "PHYS 1251", schedule_type: "LAB", seats_available: 0), :tuesday, 1000, 1150) }

    before { pair(lecture, lab) }

    it "joins the lab entry to the lecture entry" do
      result = find([ { codes: [ "PHYS 1250" ] }, { codes: [ "PHYS 1251" ], crns: [ 20900 ] } ], preferences: { open_only: false })

      expect(crn_sets(result)).to eq([ %w[20410 20900] ])
    end

    it "keeps a pinned full lab of the other code with open_only" do
      lecture.update!(seats_available: 5)
      courses = [ { codes: [ "PHYS 1250" ] }, { codes: [ "PHYS 1251" ], crns: [ 20900 ] } ]

      expect(find(courses, preferences: { open_only: true })[:count]).to eq(1)
      expect(find([ { codes: [ "PHYS 1250" ], crns: [ 20900 ] } ], preferences: { open_only: true })[:count]).to eq(1)
    end
  end

  describe "the rules of Catalog::ScheduleCheck" do
    it "leaves out a schedule with a time conflict" do
      meets(section(20410, "COMP 3350"), :monday, 1000, 1115)
      meets(section(20411, "COMP 3350", section_number: "02"), :monday, 1300, 1415)
      meets(section(20520, "MATH 2300"), :monday, 1100, 1210)

      result = find([ { codes: [ "COMP 3350" ] }, { codes: [ "MATH 2300" ] } ])

      expect(crn_sets(result)).to eq([ %w[20411 20520] ])
      result[:schedules].each do |schedule|
        check = Catalog::ScheduleCheck.new(term_uid: term.uid, crns: schedule[:crns]).call
        expect(check.values_at(:conflicts, :link_problems, :duplicates, :cancelled)).to all(be_empty)
      end
    end

    it "lets half-term sections in different halves share a time" do
      first_half  = section(20500, "MGMT 3000")
      second_half = section(20501, "MGMT 3001")
      meets(first_half, :monday, 1000, 1115, start_date: Date.new(2027, 1, 12), end_date: Date.new(2027, 2, 28))
      meets(second_half, :monday, 1000, 1115, start_date: Date.new(2027, 3, 1), end_date: Date.new(2027, 4, 20))

      expect(find([ { codes: [ "MGMT 3000" ] }, { codes: [ "MGMT 3001" ] } ])[:count]).to eq(1)
    end

    it "does not take the same course for two entries" do
      section(20520, "MATH 2300")
      section(20610, "MATH 2860")

      result = find([ { codes: [ "MATH 2300", "MATH 2860" ] }, { codes: [ "MATH 2300" ] } ])

      expect(crn_sets(result)).to eq([ %w[20610 20520] ])
    end

    it "builds schedules around sections with no meeting time" do
      section(20700, "PHIL 2100", schedule_type: "ONL")
      meets(section(20410, "COMP 3350"), :monday, 1000, 1115)

      result = find([ { codes: [ "PHIL 2100" ] }, { codes: [ "COMP 3350" ] } ])

      expect(crn_sets(result)).to eq([ %w[20700 20410] ])
      expect(result[:schedules].first[:totals]).to include(days: %w[monday], earliest_start: "10:00")
    end
  end

  describe "course entries" do
    it "takes one of several codes" do
      section(20520, "MATH 2300")
      section(20610, "MATH 2860")

      result = find([ { codes: [ "MATH 2300", "MATH2860" ] } ])

      expect(result[:schedules].map { |schedule| schedule[:courses].sole[:code] }).to eq([ "MATH 2300", "MATH 2860" ])
    end

    it "keeps only the pinned sections, even when they are full" do
      lecture = section(20230, "COMP 2280", seats_available: 0)
      pair(lecture, section(20231, "COMP 2280", schedule_type: "LAB", seats_available: 0))
      other = section(20232, "COMP 2280", seats_available: 5)
      pair(other, section(20233, "COMP 2280", schedule_type: "LAB", seats_available: 5))

      result = find([ { codes: [ "COMP 2280" ], crns: [ "20230", 20231 ] } ], preferences: { open_only: true })

      expect(crn_sets(result)).to eq([ %w[20230 20231] ])
    end

    it "applies open_only to the unpinned lab of a pinned lecture" do
      lecture = section(20230, "COMP 2280", seats_available: 0)
      pair(lecture, section(20231, "COMP 2280", schedule_type: "LAB", seats_available: 0))

      expect(find([ { codes: [ "COMP 2280" ], crns: [ 20230 ] } ], preferences: { open_only: true })[:count]).to eq(0)
    end

    it "keeps a pinned lecture and lab that Banner does not link" do
      section(20410, "COMP 1100")
      section(21202, "COMP 1100", schedule_type: "LAB", is_section_linked: true, links_fetched_at: Time.current)

      expect(crn_sets(find([ { codes: [ "COMP 1100" ], crns: [ 20410, 21202 ] } ]))).to eq([ %w[20410 21202] ])
      expect(crn_sets(find([ { codes: [ "COMP 1100" ], crns: [ 21202 ] } ]))).to eq([ %w[21202] ])
    end

    it "does not let a lab alone stand in when the lecture's own lab is cancelled" do
      lecture = section(20410, "COMP 1100")
      pair(lecture, section(20411, "COMP 1100", schedule_type: "LAB", status: :cancelled))
      section(21202, "COMP 1100", schedule_type: "LAB")

      expect(find([ { codes: [ "COMP 1100" ] } ])[:count]).to eq(0)
    end

    it "rejects the same course in two entries" do
      section(20520, "MATH 2300")

      expect { find([ { codes: [ "MATH 2300" ] }, { codes: [ "MATH2300" ] } ]) }
        .to raise_error(Catalog::FilterError, /MATH 2300 is in two course entries/)
    end

    it "rejects a pinned CRN of another course or a cancelled one" do
      section(20230, "COMP 2280")
      section(20520, "MATH 2300")
      section(20234, "COMP 2280", status: :cancelled)

      expect { find([ { codes: [ "COMP 2280" ], crns: [ 20520 ] } ]) }
        .to raise_error(Catalog::FilterError, /20520 is not a section of COMP 2280/)
      expect { find([ { codes: [ "COMP 2280" ], crns: [ 20234 ] } ]) }.to raise_error(Catalog::FilterError, /cancelled/)
    end

    it "lists a known course with no section in the term as not offered and builds the rest" do
      create(:catalog_course, subject_code: "COMP", course_number: 4960)
      section(20520, "MATH 2300")

      result = find([ { codes: [ "COMP 4960" ] }, { codes: [ "MATH 2300" ] } ])

      expect(result[:not_offered]).to eq([ "COMP 4960" ])
      expect(crn_sets(result)).to eq([ %w[20520] ])
    end

    it "finds the sections of a new code from a checked old code" do
      section(20100, "COMP 1000")
      create(:course_code_alias, from_subject_code: "COMP", from_course_number: 128, to_subject_code: "COMP",
                                 to_course_number: 1000, reviewed_at: Time.current)

      result = find([ { codes: [ "COMP 128" ] } ])

      expect(result[:schedules].sole[:courses]).to eq([ { code: "COMP 1000", crns: %w[20100] } ])
      expect(result[:not_offered]).to be_empty
    end

    it "rejects an unknown course, term, or preference" do
      section(20520, "MATH 2300")

      expect { find([ { codes: [ "ZZZZ 9999" ] } ]) }.to raise_error(Catalog::FilterError, /Unknown course ZZZZ 9999/)
      expect { find([ { codes: [ "not a code" ] } ]) }.to raise_error(Catalog::FilterError, /Unknown course/)
      expect { described_class.new({ term_uid: 1, courses: [ { codes: [ "MATH 2300" ] } ] }).call }
        .to raise_error(Catalog::FilterError, /Unknown term_uid/)
      expect { find([ { codes: [ "MATH 2300" ] } ], preferences: { lunch: true }) }
        .to raise_error(Catalog::FilterError, /Unknown preference/)
      expect { find([ { codes: [ "MATH 2300" ] } ], preferences: { days: "most" }) }
        .to raise_error(Catalog::FilterError, /days must be one of/)
      expect { find([ { codes: [ "MATH 2300" ] } ], preferences: { blocked: [ { days: [ "funday" ] } ] }) }
        .to raise_error(Catalog::FilterError, /Unknown day/)
    end

    it "bounds the size of the request" do
      courses = Array.new(Catalog::ScheduleOptions::Input::MAX_COURSES + 1) { { codes: [ "MATH 2300" ] } }

      expect { find(courses) }.to raise_error(Catalog::FilterError, /at most 10 courses/)
      expect { find([ { codes: %w[A1000 A1001 A1002 A1003 A1004 A1005] } ]) }.to raise_error(Catalog::FilterError, /at most 5 codes/)
      expect { find([ { codes: [ "MATH 2300" ] } ], preferences: { avoid: Array.new(11) { { days: [ "monday" ] } } }) }
        .to raise_error(Catalog::FilterError, /at most 10 avoid ranges/)
    end
  end

  describe "hard rules" do
    before do
      meets(section(20410, "COMP 3350"), %i[monday wednesday], 800, 915)
      meets(section(20411, "COMP 3350", section_number: "02"), %i[tuesday thursday], 1000, 1115)
      meets(section(20412, "COMP 3350", section_number: "03"), :friday, 1400, 1650)
    end

    def crns_with(preferences) = crn_sets(find([ { codes: [ "COMP 3350" ] } ], preferences: preferences)).flatten

    it "applies earliest and latest" do
      expect(crns_with(earliest: "09:00")).to eq(%w[20411 20412])
      expect(crns_with(latest: "16:00")).to eq(%w[20410 20411])
    end

    it "applies blocked ranges" do
      expect(crns_with(blocked: [ { days: [ "friday" ], after: "13:00" } ])).to eq(%w[20410 20411])
      expect(crns_with(blocked: [ { before: "09:00" } ])).to eq(%w[20411 20412])
      expect(crns_with(blocked: [ { days: %w[tuesday], after: "10:30", before: "11:00" } ])).to eq(%w[20410 20412])
    end

    it "applies a list of days off" do
      expect(crns_with(day_off: %w[friday monday])).to eq(%w[20411])
    end

    it "applies open_only with the rule of the section filter" do
      Course.find_by(crn: 20410).update!(seats_available: 3)
      Course.find_by(crn: 20411).update!(seats_available: 0)

      expect(crns_with(open_only: true)).to eq(%w[20410])
    end

    it "keeps one weekday free with day_off any" do
      meets(section(20520, "MATH 2300"), %i[monday tuesday wednesday thursday friday], 1200, 1250)
      meets(section(20521, "MATH 2300", section_number: "02"), %i[monday wednesday], 1300, 1350)

      result = find([ { codes: [ "COMP 3350" ] }, { codes: [ "MATH 2300" ] } ], preferences: { day_off: "any" })

      expect(crn_sets(result)).to all(include("20521"))
      expect(result[:count]).to eq(3)
    end
  end

  describe "ranking" do
    before do
      meets(section(20410, "COMP 3350"), %i[monday wednesday friday], 800, 850)
      meets(section(20411, "COMP 3350", section_number: "02"), %i[tuesday thursday], 1300, 1415)
    end

    it "orders by the soft rules and gives true highlights" do
      result = find([ { codes: [ "COMP 3350" ] } ], preferences: { avoid: [ { before: "10:00" } ], days: "fewer" })

      best, other = result[:schedules]
      expect(best).to include(rank: 1, crns: %w[20411], avoid_hits: 0)
      expect(best[:score]).to be > other[:score]
      expect(best[:highlights]).to eq([ "Mondays, Wednesdays and Fridays off", "Lunch break every day", "Done by 3 PM", "No classes before 1 PM" ])
      expect(other).to include(rank: 2, avoid_hits: 3)
      expect(result[:schedules].pluck(:score)).to all(be_between(0, 1))
    end

    it "spreads classes over more days with days: spread" do
      expect(find([ { codes: [ "COMP 3350" ] } ], preferences: { days: "spread" })[:schedules].first[:crns]).to eq(%w[20410])
    end

    it "prefers a lunch break and short gaps" do
      meets(section(20520, "MATH 2300"), %i[monday wednesday friday], 1115, 1345)
      meets(section(20521, "MATH 2300", section_number: "02"), %i[monday wednesday friday], 900, 950)
      courses = [ { codes: [ "COMP 3350" ] }, { codes: [ "MATH 2300" ] } ]

      expect(find(courses, preferences: { breaks: "lunch" })[:schedules].first[:crns]).not_to include("20520")
      expect(find(courses, preferences: { breaks: "tight" }, limit: 4)[:schedules].last[:crns]).to eq(%w[20410 20520])
    end

    it "scores a schedule whose meetings have no length" do
      meets(section(20700, "PHIL 2100"), :monday, 1000, 1000)

      expect(find([ { codes: [ "PHIL 2100" ] } ], preferences: { days: "spread" })[:schedules].sole[:score]).to be_between(0, 1)
    end

    it "finds the better schedules first when the search is capped" do
      stub_const("Catalog::ScheduleOptions::Search::CAP", 1)

      expect(find([ { codes: [ "COMP 3350" ] } ], preferences: { days: "fewer" })[:schedules].sole[:crns]).to eq(%w[20411])
    end

    it "gives the same order for the same request, and breaks ties by CRN" do
      results = Array.new(2) { find([ { codes: [ "COMP 3350" ] } ]) }

      expect(results.first).to eq(results.last)
      expect(results.first[:schedules].pluck(:score)).to eq([ 1.0, 1.0 ])
      expect(crn_sets(results.first)).to eq([ %w[20410], %w[20411] ])
    end

    it "returns at most limit schedules and still counts them all" do
      result = find([ { codes: [ "COMP 3350" ] } ], limit: 1)

      expect(result[:schedules].size).to eq(1)
      expect(result[:count]).to eq(2)
    end
  end

  describe "the cap and the budget" do
    before do
      %w[ENGL HIST ECON].each_with_index do |subject, index|
        8.times { |n| section(21000 + (index * 10) + n, "#{subject} 1100", section_number: n.to_s) }
      end
    end

    let(:courses) { [ { codes: [ "ENGL 1100" ] }, { codes: [ "HIST 1100" ] }, { codes: [ "ECON 1100" ] } ] }

    it "stops at 500 schedules" do
      expect(count(courses)).to eq(count: 500, capped: true)
      expect(find(courses)[:schedules].size).to eq(6)
    end

    it "stops when the budget is used up" do
      stub_const("Catalog::ScheduleOptions::Budget::NODES", 20)

      result = count(courses)

      expect(result[:capped]).to be(true)
      expect(result[:count]).to be < 500
    end

    it "gives each relax rule its own share of a second budget" do
      meets(Course.find_by(crn: 21000), :monday, 900, 950)
      allow(Catalog::ScheduleOptions::Budget).to receive(:share).and_call_original

      result = find([ { codes: [ "ENGL 1100" ], crns: [ 21000 ] }, { codes: [ "HIST 1100" ] } ],
                    preferences: { day_off: %w[monday], earliest: "08:00" })

      expect(result).to include(count: 0, capped: false)
      expect(result[:relax].sole).to include(preference: "day_off", count: 8)
      expect(Catalog::ScheduleOptions::Budget).to have_received(:share).with(2).twice
    end
  end

  describe "relax" do
    it "lists each hard rule to drop with the count it gives" do
      meets(section(20410, "COMP 3350"), %i[monday friday], 800, 915)

      result = find([ { codes: [ "COMP 3350" ] } ], preferences: { earliest: "09:00", day_off: [ "friday" ], open_only: false })

      expect(result).to include(count: 0, schedules: [])
      expect(result[:relax]).to be_empty

      result = find([ { codes: [ "COMP 3350" ] } ], preferences: { earliest: "08:00", day_off: [ "friday" ], latest: "18:00" })

      expect(result[:relax]).to eq([ { preference: "day_off", label: "Allow classes on Friday", count: 1 } ])
    end

    it "is empty when there are schedules" do
      section(20410, "COMP 3350")

      expect(find([ { codes: [ "COMP 3350" ] } ], preferences: { day_off: "any" })[:relax]).to eq([])
    end

    it "labels each rule" do
      meets(section(20410, "COMP 3350"), %i[monday tuesday wednesday thursday friday], 800, 850)

      result = find([ { codes: [ "COMP 3350" ] } ],
                    preferences: { day_off: "any", earliest: "09:00", blocked: [ { days: [ "monday" ] } ] })

      expect(result[:relax]).to be_empty
      expect(Catalog::ScheduleOptions::Preferences.parse("earliest" => "8:30", "latest" => "18:00", "day_off" => "any")
               .then { |preferences| %i[day_off earliest latest blocked open_only].map { |key| preferences.relax_label(key) } })
        .to eq([ "Allow classes every weekday", "Allow classes before 8:30 AM", "Allow classes after 6 PM",
                 "Allow classes in your blocked times", "Include full sections" ])
    end
  end

  describe "#count" do
    it "gives the same count as the full search" do
      meets(section(20410, "COMP 3350"), :monday, 1000, 1115)
      meets(section(20411, "COMP 3350", section_number: "02"), :tuesday, 1000, 1115)

      expect(count([ { codes: [ "COMP 3350" ] } ])).to eq(count: 2, capped: false)
    end
  end
end
