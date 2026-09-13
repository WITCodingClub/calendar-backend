# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Roboto Flex font" do
  let(:assembly) { Rails.application.assets }

  it "is a Propshaft asset" do
    expect(assembly.load_path.find("RobotoFlex-Regular.woff2")).to be_present
  end

  it "gets a digested URL when Propshaft compiles the Tailwind build" do
    source   = Rails.root.join("app/assets/tailwind/application.css").read
    built_as = Struct.new(:logical_path).new(Pathname.new("tailwind.css"))

    compiled = Propshaft::Compiler::CssAssetUrls.new(assembly).compile(built_as, source)

    expect(compiled).to match(%r{url\("/assets/RobotoFlex-Regular-[0-9a-f]+\.woff2"\)})
  end

  it "is served at its digested path" do
    get "/assets/#{assembly.load_path.find('RobotoFlex-Regular.woff2').digested_path}"

    expect(response).to have_http_status(:ok)
  end
end
