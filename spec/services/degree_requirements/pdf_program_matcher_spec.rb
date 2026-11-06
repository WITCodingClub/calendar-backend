# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfProgramMatcher do
  subject(:matcher) { described_class.new }

  let!(:bachelor) { create(:degree_program, name: "Widget Design Bachelor of Science", slug: "widget-design-bs", kind: "bachelor") }
  let!(:master) { create(:degree_program, name: "Widget Design Master of Science", slug: "widget-design-ms", kind: "master") }
  let!(:concentration) do
    create(:degree_program, name: "Widget Design Bachelor of Science - Gears Concentration",
                            slug: "widget-design-bs-gears", kind: "concentration")
  end

  it "takes the degree kind from the program code" do
    expect(matcher.call("WIDGET DESIGN (BWID)").program).to eq(bachelor)
    expect(matcher.call("Widget Design (MSWD)").program).to eq(master)
    expect(matcher.call("Curriculum for Widget Design (BWID)").program).to eq(bachelor)
  end

  it "matches a master by its name" do
    expect(matcher.call("Master of Widget Design (Two-Year)")).to have_attributes(program: master, plan_name: "Two Year Program")
  end

  it "matches a concentration by its full name" do
    expect(matcher.call("WIDGET DESIGN – GEARS CONCENTRATION").program).to eq(concentration)
    expect(matcher.call("Widget Design (BWID) with concentration in Gears").program).to eq(concentration)
  end

  # Without a code, the bachelor and the master both have the subject.
  it "gives nil when more than one program could match" do
    expect(matcher.call("WIDGET DESIGN")).to be_nil
  end

  it "gives nil for a program that the HTML catalogs do not have" do
    expect(matcher.call("GADGET TECHNOLOGY (BGAT)")).to be_nil
  end

  # The current catalog names programs "Computer Science, B.S.".
  it "matches the program names with a comma and B.S." do
    gadget = create(:degree_program, name: "Gadget Studies, B.S.", slug: "gadget-studies-bs")
    gears = create(:degree_program, name: "Gadget Studies, B.S. - Gears Concentration", slug: "gadget-studies-bs-gears",
                                    kind: "concentration")

    expect(matcher.call("GADGET STUDIES (BGAD)").program).to eq(gadget)
    expect(matcher.call("Gadget Studies (BGAD) with concentration in Gears").program).to eq(gears)
  end

  it "names the plan of a heading without a length Plan of Study" do
    expect(matcher.call("WIDGET DESIGN (BWID)").plan_name).to eq("Plan of Study")
  end
end
