# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::Text do
  it "puts the left half of each page before its right half" do
    expect(described_class.interleave("L1\fL2", "R1\fR2")).to eq("L1\nR1\fL2\nR2")
  end

  it "raises a degree requirements error when pdftotext is missing" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect { described_class.extract("%PDF-1.4") }.to raise_error(DegreeRequirements::Error, /pdftotext is not installed/)
  end

  it "raises when pdftotext fails" do
    allow(Open3).to receive(:capture3).and_return([ "", "Syntax Error", instance_double(Process::Status, success?: false) ])

    expect { described_class.extract("not a pdf", columns: 2) }.to raise_error(DegreeRequirements::Error, /Syntax Error/)
  end

  it "joins the ﬁ ligature into plain letters" do
    allow(Open3).to receive(:capture3).and_return([ "Certiﬁcate\u0000", "", instance_double(Process::Status, success?: true) ])

    expect(described_class.extract("%PDF-1.4")).to eq("Certificate")
  end
end
