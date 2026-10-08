# frozen_string_literal: true

FactoryBot.define do
  factory :brightspace_syllabus, class: "Brightspace::Syllabus" do
    association :course_offering, factory: :brightspace_course_offering
    sequence(:revision) { |n| "rev-#{n}" }
    title { "Syllabus" }
  end
end
