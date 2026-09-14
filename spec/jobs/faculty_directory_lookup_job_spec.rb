# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacultyDirectoryLookupJob, type: :job do
  def directory_result(faculty:)
    { success: true, faculty: faculty, total_count: faculty.size }
  end

  it "does nothing when the faculty record no longer exists" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "skips the lookup when the faculty was synced within the last 24 hours" do
    faculty = create(:faculty, directory_last_synced_at: 1.hour.ago)

    expect(FacultyDirectoryService).not_to receive(:new)

    described_class.perform_now(faculty.id)
  end

  it "updates the faculty when the directory search finds a matching email" do
    faculty = create(:faculty, email: "byrona@wit.edu", last_name: "Byron", department: nil,
                                directory_last_synced_at: nil)

    allow(FacultyDirectoryService).to receive(:new)
      .with(search: "Byron", fetch_all: false)
      .and_return(instance_double(FacultyDirectoryService, call: directory_result(faculty: [
        { display_name: "Ada Byron", email: "byrona@wit.edu", department: "Computer Science" }
      ])))

    described_class.perform_now(faculty.id)

    faculty.reload
    expect(faculty.department).to eq("Computer Science")
    expect(faculty.directory_last_synced_at).to be_present
  end

  it "stamps the sync time without changing data when no match is found" do
    faculty = create(:faculty, email: "byrona@wit.edu", last_name: "Byron", directory_last_synced_at: nil)

    allow(FacultyDirectoryService).to receive(:new)
      .with(search: "Byron", fetch_all: false)
      .and_return(instance_double(FacultyDirectoryService, call: directory_result(faculty: [])))

    described_class.perform_now(faculty.id)

    expect(faculty.reload.directory_last_synced_at).to be_present
  end

  it "does not touch the faculty record when the directory search itself fails" do
    faculty = create(:faculty, email: "byrona@wit.edu", last_name: "Byron", directory_last_synced_at: nil)

    allow(FacultyDirectoryService).to receive(:new)
      .with(search: "Byron", fetch_all: false)
      .and_return(instance_double(FacultyDirectoryService, call: { success: false, error: "HTTP 500", faculty: [], total_count: 0 }))

    described_class.perform_now(faculty.id)

    expect(faculty.reload.directory_last_synced_at).to be_nil
  end
end
