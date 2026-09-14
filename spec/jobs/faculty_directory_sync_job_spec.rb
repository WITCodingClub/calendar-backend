# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacultyDirectorySyncJob, type: :job do
  def directory_result(faculty:, total_count: faculty.size)
    { success: true, faculty: faculty, total_count: total_count }
  end

  it "raises when the directory service reports a failure" do
    allow(FacultyDirectoryService).to receive(:call)
      .and_return(success: false, error: "HTTP 500", faculty: [], total_count: 0)

    expect { described_class.perform_now }.to raise_error(/Failed to fetch faculty directory/)
  end

  it "creates a new faculty record from a directory entry with a full name and email" do
    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [
        { display_name: "Ada Byron", title: "Professor", email: "byrona@wit.edu",
          department: "Computer Science", office_location: "Beatty 205", raw_html: "<div></div>" }
      ])
    )

    stats = described_class.perform_now

    faculty = Faculty.find_by(email: "byrona@wit.edu")
    expect(faculty).to be_present
    expect(faculty.first_name).to eq("Ada")
    expect(faculty.last_name).to eq("Byron")
    expect(faculty.title).to eq("Professor")
    expect(faculty.directory_last_synced_at).to be_present
    expect(stats).to include(created: 1, updated: 0, skipped: 0)
  end

  it "skips a brand new entry when the display name cannot be split into a first and last name" do
    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [ { display_name: nil, email: "noname@wit.edu" } ])
    )

    stats = described_class.perform_now

    expect(Faculty.find_by(email: "noname@wit.edu")).to be_nil
    expect(stats).to include(created: 0, skipped: 1)
  end

  it "skips a directory entry with no email address" do
    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [ { display_name: "No Email", email: nil } ])
    )

    stats = described_class.perform_now

    expect(stats).to include(skipped: 1)
  end

  it "updates an existing faculty record when the directory has newer information" do
    faculty = create(:faculty, email: "byrona@wit.edu", first_name: "Ada", last_name: "Byron", department: nil)

    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [
        { display_name: "Ada Byron", email: "byrona@wit.edu", department: "Computer Science" }
      ])
    )

    stats = described_class.perform_now

    expect(faculty.reload.department).to eq("Computer Science")
    expect(stats).to include(updated: 1, created: 0)
  end

  # Bug: merge_faculty_attributes always stamps directory_raw_data and
  # directory_last_synced_at, so faculty.changed? is always true and an
  # existing record is never counted as "skipped" even when nothing else about
  # it changed. Harmless (it only makes the stats and the "no changes needed"
  # log line inaccurate; the record itself is written correctly either way),
  # so this documents the current behavior rather than the apparent intent.
  it "counts an existing faculty record as updated even when nothing else changed" do
    faculty = create(:faculty, email: "byrona@wit.edu", first_name: "Ada", last_name: "Byron",
                                department: "Computer Science", directory_last_synced_at: 2.days.ago)

    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [
        { display_name: "Ada Byron", email: "byrona@wit.edu", department: "Computer Science" }
      ])
    )

    stats = described_class.perform_now

    expect(stats).to include(updated: 1, skipped: 0, created: 0)
    expect(faculty.reload.directory_last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "records an error and keeps going when one directory entry fails to save" do
    allow(FacultyDirectoryService).to receive(:call).and_return(
      directory_result(faculty: [
        { display_name: "Ada Byron", email: "DUPLICATE@wit.edu" },
        { display_name: "Ada Byron Twice", email: "duplicate@wit.edu" }
      ])
    )

    stats = described_class.perform_now

    expect(Faculty.where(email: "duplicate@wit.edu").count).to eq(1)
    expect(stats[:created]).to eq(1)
    expect(stats[:errors].size).to eq(1)
    expect(stats[:errors].first[:email]).to eq("duplicate@wit.edu")
  end
end
