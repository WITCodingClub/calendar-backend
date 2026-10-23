# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseOutcomes::Recorder do
  let(:user) { create(:user) }
  let(:fall) { create(:term, uid: 202610, year: 2025, season: :fall) }
  let(:spring) { create(:term, uid: 202620, year: 2026, season: :spring) }

  def enroll(term)
    course = create(:course, term: term)
    create(:enrollment, user: user, course: course)
    course
  end

  def record(entries) = described_class.new(user, entries).call

  it "stores an outcome for each enrolled CRN and lists the others" do
    calculus = enroll(fall)
    writing = enroll(fall)
    other = create(:course, term: fall)

    results = record([ { term: "Fall 2025", courses: [
      { crn: calculus.crn.to_s, outcome: "c_or_better" },
      { crn: writing.crn, outcome: "passed_below_c" },
      { crn: other.crn.to_s, outcome: "failed" }
    ] } ])

    expect(results.map(&:as_json)).to eq([ { term: "202610", updated: 2, unknown_crns: [ other.crn.to_s ] } ])
    expect(user.course_outcomes.pluck(:crn, :outcome))
      .to contain_exactly([ calculus.crn, "c_or_better" ], [ writing.crn, "passed_below_c" ])
  end

  it "replaces the outcomes of each term it gets, and leaves the other terms" do
    kept = enroll(spring)
    create(:course_outcome, user: user, course: kept, outcome: "withdrawn")
    changed = enroll(fall)
    removed = enroll(fall)
    create(:course_outcome, user: user, course: changed, outcome: "incomplete")
    create(:course_outcome, user: user, course: removed, outcome: "failed")

    record([ { term: fall.uid, courses: [ { crn: changed.crn, outcome: "c_or_better" } ] } ])

    expect(user.course_outcomes.pluck(:crn, :outcome))
      .to contain_exactly([ kept.crn, "withdrawn" ], [ changed.crn, "c_or_better" ])
  end

  it "keeps the outcome when the catalog refresh deletes and imports the course again" do
    course = enroll(fall)
    record([ { term: fall.uid, courses: [ { crn: course.crn, outcome: "c_or_better" } ] } ])

    Enrollment.where(course: course).delete_all
    course.delete
    new_course = create(:course, term: fall, crn: course.crn)

    expect(user.course_outcomes.sole).to have_attributes(outcome: "c_or_better", course: new_course)
  end

  it "keeps the stored outcome of a CRN that is in the payload but not enrolled now" do
    course = enroll(fall)
    record([ { term: fall.uid, courses: [ { crn: course.crn, outcome: "c_or_better" } ] } ])
    user.enrollments.delete_all

    results = record([ { term: fall.uid, courses: [ { crn: course.crn, outcome: "failed" } ] } ])

    expect(results.map(&:as_json)).to eq([ { term: "202610", updated: 0, unknown_crns: [ course.crn.to_s ] } ])
    expect(user.course_outcomes.sole.outcome).to eq("c_or_better")
  end

  it "lists every CRN of a term the backend does not have" do
    results = record([ { term: "Fall 2013", courses: [ { crn: "123", outcome: "c_or_better" } ] } ])

    expect(results.map(&:as_json)).to eq([ { term: "201410", updated: 0, unknown_crns: [ "123" ] } ])
  end

  describe "invalid payloads" do
    it "rejects a term it cannot read with the invalid_term code" do
      expect { record([ { term: "Fall", courses: [] } ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError) { |error| expect(error.code).to eq("invalid_term") }
    end

    it "rejects a letter grade, a bad CRN, a repeated term, or no terms" do
      expect { record([ { term: "202610", courses: [ { crn: "1", outcome: "B+" } ] } ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /outcome must be one of/)
      expect { record([ { term: "202610", courses: [ { crn: "abc", outcome: "failed" } ] } ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /crn must be a number/)
      expect { record([ { term: "202610", courses: [] }, { term: "Fall 2025", courses: [] } ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /more than once/)
      expect { record([]) }.to raise_error(AcademicProfiles::InvalidProfileError, /non-empty/)
    end

    it "writes nothing when a later term is not valid" do
      course = enroll(fall)

      expect do
        record([ { term: fall.uid, courses: [ { crn: course.crn, outcome: "c_or_better" } ] },
                 { term: spring.uid, courses: [ { crn: "1", outcome: "A" } ] } ])
      end.to raise_error(AcademicProfiles::InvalidProfileError)

      expect(CourseOutcome.count).to eq(0)
    end
  end
end
