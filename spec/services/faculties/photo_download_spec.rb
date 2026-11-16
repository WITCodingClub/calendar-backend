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

  it "returns false after one try when the download times out" do
    stub = stub_request(:get, url).to_timeout

    expect(described_class.call(faculty, url)).to be(false)
    expect(stub).to have_been_requested.once
  end

  it "does not retry a busy server" do
    stub = stub_request(:get, url).to_return(status: 503)

    expect(described_class.call(faculty, url)).to be(false)
    expect(stub).to have_been_requested.once
  end

  it "does nothing for a url with no host" do
    expect(described_class.call(faculty, "/sites/default/files/face.jpg")).to be_nil
  end

  it "follows a redirect to another wit.edu host" do
    stub_request(:get, "https://wit.edu/photo.jpg").to_return(status: 301, headers: { "Location" => "https://www.wit.edu/photo.jpg" })
    stub_request(:get, "https://www.wit.edu/photo.jpg").to_return(status: 200, body: "synthetic image bytes")

    expect(described_class.call(faculty, "https://wit.edu/photo.jpg")).to be(true)
  end

  it "reports any other failure and returns false" do
    stub_request(:get, url).to_return(status: 200, body: "synthetic image bytes")
    allow(faculty.photo).to receive(:attach).and_raise(ActiveStorage::Error, "synthetic")
    allow(Rails.error).to receive(:report)

    expect(described_class.call(faculty, url)).to be(false)
    expect(Rails.error).to have_received(:report).with(an_instance_of(ActiveStorage::Error), handled: true, context: { faculty_id: faculty.id })
  end
end
