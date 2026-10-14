# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ScheduleCheck do
  let(:term) { create(:term, uid: 202720, season: :spring, year: 2027) }

  def section(crn, course_number: 2350, schedule_type: "LEC", credit_hours: 4, **attributes)
    create(:course, term: term, crn: crn, subject: "COMP", course_number: course_number,
                    schedule_type: schedule_type, credit_hours: credit_hours, **attributes)
  end

  def meets(course, day, from, to, **attributes)
    create(:course_meeting_time, course: course, day_of_week: day, begin_time: from, end_time: to, **attributes)
    course
  end

  def check(*crns) = described_class.new(term_uid: term.uid, crns: crns).call

  it "lists the sections and the CRNs it could not use" do
    meets(section(20397), :monday, 1000, 1115)
    section(20398, status: :cancelled)

    result = check(20397, 20398, 99999)

    expect(result[:sections].pluck(:crn)).to eq([ 20397 ])
    expect(result[:sections].first[:meeting_times]).to eq([ { day: "monday", begin_time: "10:00", end_time: "11:15" } ])
    expect(result[:not_found]).to eq([ 20398, 99999 ])
    expect(result[:cancelled]).to eq([ 20398 ])
  end

  it "finds two sections that meet at the same time" do
    meets(section(20397), :monday, 1000, 1115)
    meets(section(20111, course_number: 2860), :monday, 1100, 1210)

    expect(check(20397, 20111)[:conflicts]).to eq([ { crns: [ 20397, 20111 ], day: "monday", times: %w[10:00-11:15 11:00-12:10] } ])
  end

  it "does not count meetings that only touch, or meet on other days" do
    meets(section(20397), :monday, 1000, 1115)
    meets(section(20111, course_number: 2860), :monday, 1115, 1230)
    meets(section(20112, course_number: 2870), :tuesday, 1000, 1115)

    expect(check(20397, 20111, 20112)[:conflicts]).to be_empty
  end

  it "does not count half-term sections whose dates do not overlap" do
    first_half  = section(20500, course_number: 3000)
    second_half = section(20501, course_number: 3001)
    meets(first_half, :monday, 1000, 1115, start_date: Date.new(2027, 1, 12), end_date: Date.new(2027, 2, 28))
    meets(second_half, :monday, 1000, 1115, start_date: Date.new(2027, 3, 1), end_date: Date.new(2027, 4, 20))

    expect(check(20500, 20501)[:conflicts]).to be_empty
  end

  describe "linked sections" do
    let(:lecture) { section(20452, course_number: 4960, is_section_linked: true, link_identifier: "A2", links_fetched_at: Time.current) }
    let(:lab)     { section(20455, course_number: 4960, schedule_type: "LAB", credit_hours: nil, is_section_linked: true, link_identifier: "B1", links_fetched_at: Time.current) }

    before do
      create(:section_link, course: lecture, linked_course: lab, credit_hours: 0)
      create(:section_link, course: lab, linked_course: lecture, credit_hours: 4)
    end

    it "accepts Banner's pair even when the link identifiers disagree" do
      expect(check(20452, 20455)[:link_problems]).to be_empty
    end

    it "names Banner's partners when one is missing" do
      problem = check(20452)[:link_problems].sole

      expect(problem).to include(crn: 20452, problem: "missing_partner", source: "banner",
                                 partner_crns: [ 20455 ], partner_options: [ [ 20455 ] ])
      expect(problem[:message]).to include("20455")
    end

    it "treats a section with no Banner partners as standing alone" do
      alone = section(21202, course_number: 1100, schedule_type: "LAB", is_section_linked: true, links_fetched_at: Time.current)

      expect(check(alone.crn)[:link_problems]).to be_empty
    end

    it "falls back to the link identifiers before Banner's pairs are fetched" do
      unfetched_lecture = section(20396, is_section_linked: true, link_identifier: "A1")
      section(20400, schedule_type: "LAB", is_section_linked: true, link_identifier: "B1")

      problem = check(unfetched_lecture.crn)[:link_problems].sole

      expect(problem).to include(problem: "missing_partner", source: "link_identifier", partner_crns: [ 20400 ])
    end

    it "flags a linked section with no known partner when Banner's pairs are not fetched" do
      orphan = section(20460, course_number: 4970, is_section_linked: true, link_identifier: "A9")

      expect(check(orphan.crn)[:link_problems].sole).to include(problem: "unverified_link", partner_crns: [])
    end

    it "counts Banner's credits: the lab is 0" do
      expect(check(20452, 20455)[:totals][:credit_hours]).to eq(4)
    end
  end

  it "finds the same course chosen twice" do
    section(20397)
    section(20399)

    expect(check(20397, 20399)[:duplicates]).to eq([ { course_code: section_code(20397), crns: [ 20397, 20399 ] } ])
  end

  def section_code(crn) = Catalog::SectionSerializer.course_code_for(Course.find_by(crn: crn)).split("-").first

  it "counts a course once when old rows give its lab the lecture's credits" do
    section(20397)
    section(20401, schedule_type: "LAB", credit_hours: 4)
    section(20111, course_number: 2860)

    expect(check(20397, 20401, 20111)[:totals][:credit_hours]).to eq(8)
  end

  it "adds up the week" do
    meets(section(20111, course_number: 2860), :monday, 800, 910)
    meets(section(20112, course_number: 2870), :wednesday, 800, 910)
    meets(section(20397), :friday, 1500, 1645)

    totals = check(20111, 20112, 20397)[:totals]

    expect(totals).to eq(credit_hours: 12, days: %w[monday wednesday friday], earliest_start: "08:00",
                         latest_end: "16:45", meetings_before_nine: 2)
  end

  it "refuses an empty list, too many CRNs, and an unknown term" do
    expect { check }.to raise_error(Catalog::FilterError, /at least one/)
    expect { check(*1..31) }.to raise_error(Catalog::FilterError, /at most 30/)
    expect { described_class.new(term_uid: 1, crns: [ 1 ]).call }.to raise_error(Catalog::FilterError, /Unknown term_uid/)
  end
end
