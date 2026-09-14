# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateFacultyRatingsJob, type: :job do
  let(:base_url) { RateMyProfessorService::BASE_URL }

  def stub_graphql(operation_name, fixture:)
    stub_request(:post, base_url)
      .with(body: hash_including("operationName" => operation_name))
      .to_return(status: 200, body: file_fixture("rate_my_professor/#{fixture}").read,
                 headers: { "Content-Type" => "application/json" })
  end

  it "does nothing when the faculty does not teach any courses" do
    faculty = create(:faculty)

    described_class.perform_now(faculty.id)

    expect(WebMock).not_to have_requested(:post, base_url)
  end

  it "leaves the faculty without an rmp_id when the search finds no match" do
    faculty = create(:faculty, first_name: "Nobody", last_name: "Real")
    create(:course_faculty, faculty: faculty)
    stub_graphql("NewSearchTeachersQuery", fixture: "search_empty.json")

    described_class.perform_now(faculty.id)

    expect(faculty.reload.rmp_id).to be_nil
    expect(WebMock).not_to have_requested(:post, base_url).with(body: hash_including("operationName" => "TeacherRatingsPageQuery"))
  end

  it "links the faculty to the matching RateMyProfessors teacher, then fetches ratings" do
    faculty = create(:faculty, first_name: "Ada", last_name: "Byron")
    create(:course_faculty, faculty: faculty)
    stub_graphql("NewSearchTeachersQuery", fixture: "search_results.json")
    stub_graphql("TeacherRatingsPageQuery", fixture: "teacher_details.json")
    stub_graphql("RatingsListQuery", fixture: "ratings_empty.json")

    described_class.perform_now(faculty.id)

    expect(faculty.reload.rmp_id).to eq("VGVhY2hlci0xMjM0NTY=")
  end

  it "does not fetch ratings when the matched rmp_id is already taken by another faculty" do
    create(:faculty, rmp_id: "VGVhY2hlci0xMjM0NTY=")
    faculty = create(:faculty, first_name: "Ada", last_name: "Byron")
    create(:course_faculty, faculty: faculty)
    stub_graphql("NewSearchTeachersQuery", fixture: "search_results.json")

    described_class.perform_now(faculty.id)

    expect(faculty.reload.rmp_id).to be_nil
    expect(WebMock).not_to have_requested(:post, base_url).with(body: hash_including("operationName" => "TeacherRatingsPageQuery"))
  end

  context "with an rmp_id already assigned" do
    let(:faculty) { create(:faculty, rmp_id: "VGVhY2hlci0xMjM0NTY=") }

    before do
      create(:course_faculty, faculty: faculty)
      stub_graphql("TeacherRatingsPageQuery", fixture: "teacher_details.json")
    end

    it "stores the ratings, distribution, tags, related professors, and raw data" do
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "RatingsListQuery", "variables" => hash_including("cursor" => nil)))
        .to_return(status: 200, body: file_fixture("rate_my_professor/ratings_page1.json").read,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "RatingsListQuery", "variables" => hash_including("cursor" => "cursor-1")))
        .to_return(status: 200, body: file_fixture("rate_my_professor/ratings_page2.json").read,
                   headers: { "Content-Type" => "application/json" })

      described_class.perform_now(faculty.id)

      expect(faculty.rmp_ratings.pluck(:rmp_id)).to contain_exactly("1", "2")
      first_rating = faculty.rmp_ratings.find_by(rmp_id: "1")
      expect(first_rating.course_name).to eq("COMP1050")
      expect(first_rating.would_take_again).to be(true)
      expect(first_rating.comment).to eq("Fake review one, purely synthetic test data.")

      distribution = faculty.reload.rating_distribution
      expect(distribution.total).to eq(42)
      expect(distribution.avg_rating.to_f).to eq(4.5)

      expect(faculty.teacher_rating_tags.pluck(:tag_name)).to contain_exactly("Caring", "Tough Grader")

      related = faculty.related_professors.sole
      expect(related.rmp_id).to eq("VGVhY2hlci02NTQzMjE=")
      expect(related.first_name).to eq("Grace")

      expect(faculty.rmp_raw_data["metadata"]["total_ratings_fetched"]).to eq(2)
    end

    it "links a related professor to an existing faculty record with the same rmp_id" do
      related_faculty = create(:faculty, rmp_id: "VGVhY2hlci02NTQzMjE=")
      stub_graphql("RatingsListQuery", fixture: "ratings_empty.json")

      described_class.perform_now(faculty.id)

      related = faculty.related_professors.sole
      expect(related.related_faculty).to eq(related_faculty)
    end

    it "propagates the error when the ratings request times out" do
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "RatingsListQuery"))
        .to_timeout

      expect { described_class.perform_now(faculty.id) }.to raise_error(Faraday::ConnectionFailed)
    end
  end
end
