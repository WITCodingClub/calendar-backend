# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: faculties
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
#  embedding_digest         :string(64)
#  employee_type            :string
#  first_name               :string           not null
#  last_name                :string           not null
#  middle_name              :string
#  office_location          :string
#  phone                    :string
#  photo_url                :string
#  rmp_raw_data             :jsonb
#  school                   :string
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  rmp_id                   :string
#
# Indexes
#
#  index_faculties_on_department                (department)
#  index_faculties_on_directory_last_synced_at  (directory_last_synced_at)
#  index_faculties_on_directory_raw_data        (directory_raw_data) USING gin
#  index_faculties_on_email                     (email) UNIQUE
#  index_faculties_on_embedding                 (embedding vector_cosine_ops) USING hnsw
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_lower_email               (lower((email)::text))
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
RSpec.describe Faculty, type: :model do
  subject { create(:faculty) }

  it { is_expected.to have_many(:course_faculties).dependent(:destroy) }
  it { is_expected.to have_many(:courses).through(:course_faculties) }
  it { is_expected.to have_many(:rmp_ratings).dependent(:destroy) }
  it { is_expected.to have_many(:related_professors).dependent(:destroy) }
  it { is_expected.to have_one(:rating_distribution).dependent(:destroy) }
  it { is_expected.to have_many(:teacher_rating_tags).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:email) }
  it { is_expected.to validate_presence_of(:first_name) }
  it { is_expected.to validate_presence_of(:last_name) }
  it { is_expected.to validate_uniqueness_of(:rmp_id).allow_nil }

  describe "weekly RateMyProfessor refresh" do
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Date.new(2026, 10, 1)) { example.run } }

    let(:current_term) { create(:term, year: 2026, season: :fall) }
    let(:next_term)    { create(:term, year: 2027, season: :spring) }
    let(:past_term)    { create(:term, year: 2025, season: :spring) }

    def teaching(term)
      create(:faculty).tap { |faculty| create(:course_faculty, faculty: faculty, course: create(:course, term: term)) }
    end

    let!(:current_faculty) { teaching(current_term) }
    let!(:future_faculty)  { teaching(next_term) }
    let!(:past_faculty)    { teaching(past_term) }

    it "selects faculty who teach in the current term or a later term" do
      create(:faculty)

      expect(described_class.teaching_current_or_future).to contain_exactly(current_faculty, future_faculty)
    end

    it "lists a faculty with courses in many current terms once" do
      create(:course_faculty, faculty: current_faculty, course: create(:course, term: next_term))

      expect(described_class.teaching_current_or_future.to_a.count(current_faculty)).to eq(1)
    end

    it "enqueues a ratings update only for current and future faculty" do
      expect { described_class.update_all_ratings! }
        .to have_enqueued_job(Faculties::UpdateRatingsJob).exactly(:twice)
      expect(Faculties::UpdateRatingsJob).not_to have_been_enqueued.with(past_faculty.id)
    end
  end

  describe "#similar_instructors" do
    let(:term) { create(:term) }

    def teaching_faculty(angle)
      person = give_embedding(create(:faculty), angle)
      create(:course, term: term).faculties << person
      person
    end

    it "returns the closest instructors who teach, nearest first" do
      source = teaching_faculty(0.0)
      near   = teaching_faculty(0.10)
      far    = teaching_faculty(0.90)

      expect(source.similar_instructors).to eq([ near, far ])
    end

    it "leaves out people who teach nothing" do
      source = teaching_faculty(0.0)
      give_embedding(create(:faculty), 0.01)

      expect(source.similar_instructors).to be_empty
    end

    it "stops at the limit" do
      source = teaching_faculty(0.0)
      teaching_faculty(0.10)
      teaching_faculty(0.20)

      expect(source.similar_instructors(limit: 1).length).to eq(1)
    end

    it "returns nothing until the instructor has a vector" do
      expect(create(:faculty).similar_instructors).to be_empty
    end
  end

  describe "#embedding_text" do
    it "reads the directory facts a student would search by" do
      faculty = create(:faculty, first_name: "Ada", last_name: "Lovelace", display_name: nil,
                                 title: "Professor", department: "Computer Science", school: "School of Computing")

      expect(faculty.embedding_text).to eq("Ada Lovelace. Professor. Computer Science. School of Computing")
    end

    it "leaves out the fields the directory has not filled" do
      faculty = create(:faculty, first_name: "Ada", last_name: "Lovelace", middle_name: nil, display_name: nil,
                                 title: nil, department: nil, school: nil)

      expect(faculty.embedding_text).to eq("Ada Lovelace")
    end
  end

  describe "directory lookup after create" do
    include ActiveJob::TestHelper

    it "enqueues the lookup after the transaction commits" do
      expect do
        ActiveRecord::Base.transaction(requires_new: true) do
          create(:faculty)

          expect(Faculties::DirectoryLookupJob).not_to have_been_enqueued
        end
      end.to have_enqueued_job(Faculties::DirectoryLookupJob).with(a_kind_of(Integer))
    end

    it "does not enqueue the lookup when the transaction rolls back" do
      expect do
        ActiveRecord::Base.transaction(requires_new: true) do
          create(:faculty)
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(Faculties::DirectoryLookupJob)
    end
  end

  describe "#update_photo_from_url!" do
    it "returns false when the photo download times out" do
      stub_request(:get, "https://photos.example.test/face.jpg").to_timeout

      expect(create(:faculty).update_photo_from_url!("https://photos.example.test/face.jpg")).to be(false)
    end
  end

  describe "simple scopes" do
    it "filters by employee type" do
      faculty = create(:faculty, employee_type: "faculty")
      staff = create(:faculty, employee_type: "staff")

      expect(described_class.faculty_only).to contain_exactly(faculty)
      expect(described_class.staff_only).to contain_exactly(staff)
    end

    it "filters by school and department" do
      match = create(:faculty, school: "School of Computing", department: "Computer Science")
      create(:faculty, school: "School of Arts", department: "Design")

      expect(described_class.by_school("School of Computing")).to contain_exactly(match)
      expect(described_class.by_department("Computer Science")).to contain_exactly(match)
    end

    it "splits faculty by courses" do
      teacher = create(:faculty)
      idle = create(:faculty)
      create(:course_faculty, faculty: teacher, course: create(:course))

      expect(described_class.with_courses).to contain_exactly(teacher)
      expect(described_class.without_courses).to contain_exactly(idle)
    end

    it "splits faculty by directory data and finds stale syncs" do
      fresh = create(:faculty, directory_last_synced_at: 1.day.ago)
      stale = create(:faculty, directory_last_synced_at: 8.days.ago)
      never = create(:faculty)

      expect(described_class.with_directory_data).to contain_exactly(fresh, stale)
      expect(described_class.needs_directory_sync).to contain_exactly(stale, never)
    end
  end

  describe "name helpers" do
    let(:faculty) { build(:faculty, first_name: "Ada", middle_name: "King", last_name: "Lovelace", display_name: nil, title: "Professor") }

    it "#full_name prefers the display name" do
      expect(build(:faculty, display_name: "Dr. A. Lovelace").full_name).to eq("Dr. A. Lovelace")
    end

    it "#full_name joins the name parts" do
      expect(faculty.full_name).to eq("Ada King Lovelace")
      expect(build(:faculty, first_name: "Ada", middle_name: nil, last_name: "Lovelace", display_name: nil).full_name).to eq("Ada Lovelace")
    end

    it "#formal_name adds the title" do
      expect(faculty.formal_name).to eq("Professor Ada King Lovelace")
      expect(build(:faculty, first_name: "Ada", middle_name: nil, last_name: "Lovelace", title: "").formal_name).to eq("Ada Lovelace")
    end

    it "#initials and #u_name use the first letters" do
      expect(faculty.initials).to eq("AL")
      expect(faculty.u_name).to eq(fwd: "A. Lovelace", rev: "Lovelace, A.")
    end
  end

  describe "RateMyProfessor stats" do
    let(:faculty) { create(:faculty) }

    it "#rmp_stats is nil without a distribution" do
      expect(faculty.rmp_stats).to be_nil
    end

    it "#rmp_stats reads the distribution" do
      create(:rating_distribution, faculty: faculty, avg_rating: 4.5, avg_difficulty: 3.0, num_ratings: 12, would_take_again_percent: 75.0)

      expect(faculty.reload.rmp_stats).to eq(avg_rating: 4.5, avg_difficulty: 3.0, num_ratings: 12, would_take_again_percent: 75.0)
    end

    it "#calculate_rating_stats is empty without ratings" do
      expect(faculty.calculate_rating_stats).to eq({})
    end

    it "#calculate_rating_stats averages the ratings" do
      create(:rmp_rating, faculty: faculty, clarity_rating: 5, difficulty_rating: 2, would_take_again: true)
      create(:rmp_rating, faculty: faculty, clarity_rating: 4, difficulty_rating: 3, would_take_again: false)
      create(:rmp_rating, faculty: faculty, clarity_rating: 3, difficulty_rating: 4, would_take_again: nil)

      expect(faculty.calculate_rating_stats).to eq(avg_rating: 4.0, avg_difficulty: 3.0, num_ratings: 3, would_take_again_percent: 50.0)
    end

    it "#calculate_rating_stats has no percent when nobody answered" do
      create(:rmp_rating, faculty: faculty, clarity_rating: 5, difficulty_rating: 2, would_take_again: nil)

      expect(faculty.calculate_rating_stats[:would_take_again_percent]).to be_nil
    end
  end

  describe "#matched_related_faculty" do
    it "returns related professors that exist as faculty" do
      faculty = create(:faculty)
      related = create(:faculty)
      create(:related_professor, faculty: faculty, related_faculty_id: related.id)
      create(:related_professor, faculty: faculty, related_faculty_id: nil)

      expect(faculty.matched_related_faculty).to contain_exactly(related)
    end
  end

  describe "job wrappers" do
    include ActiveJob::TestHelper

    let(:faculty) { create(:faculty, directory_last_synced_at: Time.current) }

    it "enqueues a ratings update and a directory sync" do
      expect { faculty.update_ratings! }.to have_enqueued_job(Faculties::UpdateRatingsJob).with(faculty.id)
      expect { faculty.sync_from_directory! }.to have_enqueued_job(Faculties::DirectoryLookupJob).with(faculty.id)
    end

    it "runs the jobs now" do
      allow(Faculties::UpdateRatingsJob).to receive(:perform_now)
      allow(Faculties::DirectoryLookupJob).to receive(:perform_now)

      faculty.update_ratings_now!
      faculty.sync_from_directory_now!

      expect(Faculties::UpdateRatingsJob).to have_received(:perform_now).with(faculty.id)
      expect(Faculties::DirectoryLookupJob).to have_received(:perform_now).with(faculty.id)
    end

    it ".sync_all_from_directory! enqueues the sync job" do
      expect { described_class.sync_all_from_directory! }.to have_enqueued_job(Faculties::DirectorySyncJob)
    end
  end

  describe "directory data flags" do
    it "needs data when never synced and no raw data" do
      faculty = build(:faculty)

      expect([ faculty.has_directory_data?, faculty.needs_directory_data? ]).to eq([ false, true ])
    end

    it "has data when synced or when raw data exists" do
      expect(build(:faculty, directory_last_synced_at: Time.current).has_directory_data?).to be(true)
      expect(build(:faculty, directory_raw_data: { "mail" => "x" }).has_directory_data?).to be(true)
    end

    it "#directory_data_age is nil until synced, then counts seconds" do
      expect(build(:faculty).directory_data_age).to be_nil
      expect(build(:faculty, directory_last_synced_at: 2.hours.ago).directory_data_age).to be_within(5).of(7200)
    end

    it "#teaches_courses? reflects the courses" do
      faculty = create(:faculty, directory_last_synced_at: Time.current)

      expect(faculty.teaches_courses?).to be(false)
      create(:course_faculty, faculty: faculty, course: create(:course))
      expect(faculty.teaches_courses?).to be(true)
    end
  end

  describe "directory lookup throttle" do
    include ActiveJob::TestHelper

    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    it "skips the individual lookup right after a full sync" do
      Rails.cache.write("faculty_directory_last_full_sync_at", 1.hour.ago)

      expect { create(:faculty) }.not_to have_enqueued_job(Faculties::DirectoryLookupJob)
    end

    it "looks up again when the full sync is older than a day" do
      Rails.cache.write("faculty_directory_last_full_sync_at", 2.days.ago)

      expect { create(:faculty) }.to have_enqueued_job(Faculties::DirectoryLookupJob)
    end

    it "does not look up a faculty that has directory data" do
      expect { create(:faculty, directory_last_synced_at: Time.current) }.not_to have_enqueued_job(Faculties::DirectoryLookupJob)
    end
  end

  describe "RateMyProfessor ids and raw data" do
    it "#rmp_numeric_id is nil without an id" do
      expect(build(:faculty, rmp_id: nil).rmp_numeric_id).to be_nil
    end

    it "#rmp_numeric_id decodes a Teacher id" do
      expect(build(:faculty, rmp_id: Base64.strict_encode64("Teacher-123456")).rmp_numeric_id).to eq("123456")
    end

    it "#rmp_numeric_id returns the raw id when it is not a numeric Teacher id" do
      encoded = Base64.strict_encode64("Teacher-abc")

      expect(build(:faculty, rmp_id: encoded).rmp_numeric_id).to eq(encoded)
      expect(build(:faculty, rmp_id: "plain-id").rmp_numeric_id).to eq("plain-id")
    end

    it "#rmp_teacher_node and #rmp_all_ratings_raw read the raw data" do
      faculty = build(:faculty, rmp_raw_data: { "teacher" => { "data" => { "node" => { "id" => "t1" } } }, "all_ratings" => [ { "id" => "r1" } ] })

      expect(faculty.rmp_teacher_node).to eq("id" => "t1")
      expect(faculty.rmp_all_ratings_raw).to eq([ { "id" => "r1" } ])
    end

    it "returns safe defaults without raw data" do
      faculty = build(:faculty, rmp_raw_data: nil)

      expect(faculty.rmp_teacher_node).to be_nil
      expect(faculty.rmp_all_ratings_raw).to eq([])
      expect(faculty.rmp_last_updated).to be_nil
    end

    it "#rmp_last_updated parses the timestamp" do
      faculty = build(:faculty, rmp_raw_data: { "metadata" => { "last_updated_at" => "2026-09-01T12:00:00Z" } })

      expect(faculty.rmp_last_updated).to eq(Time.utc(2026, 9, 1, 12))
    end

    it "#rmp_last_updated is nil for a bad timestamp" do
      faculty = build(:faculty, rmp_raw_data: { "metadata" => { "last_updated_at" => "not a date" } })

      expect(faculty.rmp_last_updated).to be_nil
    end
  end

  describe "#photo_display_url" do
    it "falls back to the photo url" do
      expect(build(:faculty, photo_url: "https://photos.example.test/a.jpg").photo_display_url).to eq("https://photos.example.test/a.jpg")
    end

    it "uses the blob path when a photo is attached" do
      faculty = create(:faculty)
      faculty.photo.attach(io: StringIO.new("synthetic image bytes"), filename: "a.jpg", content_type: "image/jpeg")

      expect(faculty.photo_display_url).to start_with("/rails/active_storage/blobs/")
    end
  end

  describe "#update_photo_from_url! downloads" do
    let(:url) { "https://photos.example.test/face.jpg" }
    let(:faculty) { create(:faculty, email: "synthetic.person@wit.edu", directory_last_synced_at: Time.current) }

    it "does nothing for a blank or placeholder url" do
      expect(faculty.update_photo_from_url!("")).to be_nil
      expect(faculty.update_photo_from_url!("https://photos.example.test/placeholder.png")).to be_nil
      expect(faculty.update_photo_from_url!("https://photos.example.test/Icon_User.png")).to be_nil
    end

    it "attaches the photo and stores the url" do
      stub_request(:get, url).to_return(status: 200, body: "synthetic image bytes", headers: { "Content-Type" => "image/jpeg" })

      expect(faculty.update_photo_from_url!(url)).to be(true)
      expect(faculty.photo).to be_attached
      expect(faculty.photo.filename.to_s).to eq("synthetic.person_photo.jpg")
      expect(faculty.reload.photo_url).to eq(url)
    end

    it "names the file with a jpg extension when the url has none" do
      stub_request(:get, "https://photos.example.test/face").to_return(status: 200, body: "synthetic image bytes", headers: { "Content-Type" => "image/jpeg" })

      faculty.update_photo_from_url!("https://photos.example.test/face")

      expect(faculty.photo.filename.to_s).to eq("synthetic.person_photo.jpg")
    end

    it "does not download again when the same photo is attached" do
      stub = stub_request(:get, url).to_return(status: 200, body: "synthetic image bytes", headers: { "Content-Type" => "image/jpeg" })
      faculty.update_photo_from_url!(url)

      expect(faculty.update_photo_from_url!(url)).to be_nil
      expect(stub).to have_been_requested.once
    end

    it "reports an HTTP error and returns false" do
      stub_request(:get, url).to_return(status: 404)
      allow(Rails.error).to receive(:report)

      expect(faculty.update_photo_from_url!(url)).to be(false)
      expect(Rails.error).to have_received(:report).with(an_instance_of(OpenURI::HTTPError), handled: true, context: { faculty_id: faculty.id })
    end
  end
end
