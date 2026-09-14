# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Factories" do
  FactoryBot.factories.each do |factory|
    next if factory.name.to_s.start_with?("_")

    describe "#{factory.name} factory" do
      it "builds a valid record" do
        expect(build(factory.name)).to be_valid
      end

      it "creates a persisted record" do
        expect(create(factory.name)).to be_persisted
      end
    end

    factory.defined_traits.map(&:name).each do |trait_name|
      describe "#{factory.name} factory with :#{trait_name} trait" do
        it "builds a valid record" do
          expect(build(factory.name, trait_name)).to be_valid
        end

        it "creates a persisted record" do
          expect(create(factory.name, trait_name)).to be_persisted
        end
      end
    end
  end
end
