# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::PhotoDownload do
  let(:url) { "https://photos.example.test/face.jpg" }
  let(:faculty) { create(:faculty, email: "synthetic.person@wit.edu", directory_last_synced_at: Time.current) }

  it "does nothing for a blank or placeholder url" do
    expect(described_class.call(faculty, "")).to be_nil
    expect(described_class.call(faculty, "https://photos.example.test/placeholder.png")).to be_nil
    expect(described_class.call(faculty, "https://photos.example.test/Icon_User.png")).to be_nil
  end

  it "attaches the photo and stores the url" do
    stub_request(:get, url).with(headers: { "User-Agent" => HttpFetcher::USER_AGENT })
                           .to_return(status: 200, body: "synthetic image bytes", headers: { "Content-Type" => "image/jpeg" })

    expect(described_class.call(faculty, url)).to be(true)
    expect(faculty.photo).to be_attached
    expect(faculty.photo.filename.to_s).to eq("synthetic.person_photo.jpg")
    expect(faculty.reload.photo_url).to eq(url)
  end

  it "names the file with a jpg extension when the url has none" do
    stub_request(:get, "https://photos.example.test/face").to_return(status: 200, body: "synthetic image bytes")

    described_class.call(faculty, "https://photos.example.test/face")

    expect(faculty.photo.filename.to_s).to eq("synthetic.person_photo.jpg")
  end

  it "does not download again when the same photo is attached" do
    stub = stub_request(:get, url).to_return(status: 200, body: "synthetic image bytes")
    described_class.call(faculty, url)

    expect(described_class.call(faculty, url)).to be_nil
    expect(stub).to have_been_requested.once
  end

  it "reports an HTTP error and returns false" do
    stub_request(:get, url).to_return(status: 404)
    allow(Rails.error).to receive(:report)

    expect(described_class.call(faculty, url)).to be(false)
    expect(Rails.error).to have_received(:report).with(an_instance_of(described_class::Error), handled: true, context: { faculty_id: faculty.id })
  end

  it "returns false when the download times out" do
    stub_request(:get, url).to_timeout

    expect(described_class.call(faculty, url)).to be(false)
  end
end
