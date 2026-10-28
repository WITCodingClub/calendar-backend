# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::Prompts do
  def text(prompt, args = {})
    prompt.template(args).to_h.dig(:messages, 0, :content, :text)
  end

  def expect_in_order(body, names)
    names.each_cons(2) { |first, second| expect(body.index(first)).to be < body.index(second) }
  end

  it "lists each prompt one time, with a title, a description, and only optional arguments" do
    expect(described_class.names).to eq(%w[plan_term_schedule check_my_schedule plan_degree_progression find_class_for_free_time])
    described_class.all.each do |prompt|
      expect(prompt.title).to be_present
      expect(prompt.description).to be_present
      expect(prompt.arguments.map(&:required)).to all(be(false))
    end
  end

  it "finds a prompt by name" do
    expect(described_class.find("check_my_schedule")).to eq(McpTools::Prompts::CheckMySchedule)
    expect(described_class.find("drop_tables")).to be_nil
  end

  describe "every prompt" do
    described_class.all.each do |prompt|
      it "#{prompt.name_value} gives one user message with the override and advisor messages, with and without arguments" do
        [ {}, prompt.argument_names.index_with { "x" } ].each do |args|
          result = prompt.template(args).to_h

          expect(result[:description]).to eq(prompt.description)
          expect(result[:messages].size).to eq(1)
          expect(result[:messages].first).to include(role: "user", content: hash_including(type: "text"))
          expect(text(prompt, args)).to include("program director", "academic advisor", McpTools::Prompts::BasePrompt::ASK)
          expect(text(prompt, args)).to include(McpTools::Prompts::BasePrompt::OVERRIDE)
        end
      end
    end
  end

  describe "the term argument" do
    let(:prompt) { McpTools::Prompts::PlanTermSchedule }
    let!(:term) { create(:term, year: 2031, season: :spring) }

    it "takes a term uid or a term name" do
      expect(text(prompt, { "term" => term.uid.to_s })).to include("Term: Spring 2031 (term_uid #{term.uid}).")
      expect(text(prompt, { term: "spring 2031" })).to include("Term: Spring 2031 (term_uid #{term.uid}).")
    end

    it "tells the model to ask for a term that does not exist" do
      expect(text(prompt, { "term" => "Winter 1999" })).to include('I asked for "Winter 1999"', "ask me which term I mean")
    end

    it "skips summer: in spring, the default is the fall term, and the model confirms it" do
      fall = create(:term, year: 2031, season: :fall)
      create(:term, year: 2031, season: :summer)
      allow(Term).to receive(:current).and_return(term)

      body = text(prompt)

      expect(body).to include("Use Fall 2031 (term_uid #{fall.uid}), the next fall or spring term", "ask me to confirm the term")
      expect(text(McpTools::Prompts::FindClassForFreeTime)).to include("Use Fall 2031")
    end

    it "uses the spring term in fall and in summer" do
      spring = create(:term, year: 2032, season: :spring)
      allow(Term).to receive(:current).and_return(create(:term, year: 2031, season: :fall))
      expect(text(prompt)).to include("Use Spring 2032 (term_uid #{spring.uid})")

      allow(Term).to receive(:current).and_return(create(:term, year: 2032, season: :summer))
      expect(text(prompt)).to include("The next fall or spring term is Fall 2032", "not published yet")
    end

    it "tells the model to ask when there is no current term" do
      allow(Term).to receive(:current).and_return(nil)

      expect(text(prompt)).to include("Call list_terms, then ask me which term I mean")
    end
  end

  describe ".validate_arguments!" do
    let(:prompt) { McpTools::Prompts::PlanTermSchedule }

    it "takes nil or an object of text and numbers" do
      expect { prompt.validate_arguments!(nil) }.not_to raise_error
      expect { prompt.validate_arguments!({ term: 202710, courses: "COMP 2350" }) }.not_to raise_error
    end

    it "raises Invalid params for arguments that are not an object of text" do
      [ "term", [ 1 ], { term: { uid: 1 } }, { courses: [ "COMP 2350" ] } ].each do |args|
        expect { prompt.validate_arguments!(args) }.to raise_error(MCP::Server::RequestHandlerError) { |error|
          expect(error.error_code).to eq(-32_602)
        }
      end
    end
  end

  describe McpTools::Prompts::PlanTermSchedule do
    it "names the tools in order and asks for the missing facts" do
      body = text(described_class)

      expect_in_order(body, %w[list_terms my_course_history get_course search_sections check_schedule])
      expect(body).to include("Ask me which courses I want", "Ask me one time about start and end times")
      expect(body).to include("check_schedule must show no conflicts")
      expect(body).to include("If a prerequisite has a min_grade, ask me for my grade")
    end

    it "tells the student how to register: the time ticket, the RAC, and electives not yet listed" do
      body = text(described_class)

      expect(body).to include(described_class::REGISTRATION)
      expect(body).to include("time ticket", "Registration Alternate PIN (RAC)", "dean or associate dean")
      expect_in_order(body, [ "check_schedule must show no conflicts", described_class::REGISTRATION, McpTools::Prompts::BasePrompt::ADVISOR ])
    end

    it "gives the course codes and the preferences of the student" do
      body = text(described_class, { "courses" => "comp2350, Calculus II;MATH-1750", "preferences" => "no 8am \"classes\"" })

      expect(body).to include("Courses I want: COMP 2350, MATH 1750.", "call search_courses to find it")
      expect(body).to include("My preferences: \"no 8am 'classes'\"")
    end

    it "sends courses with no code to search_courses" do
      expect(text(described_class, { "courses" => "Data Structures" })).to include('Courses I want: "Data Structures". Call search_courses')
    end

    it "cuts a long argument" do
      limit = McpTools::Prompts::BasePrompt::MAX_ARGUMENT_LENGTH
      body  = text(described_class, { "preferences" => "a" * 2_000 })

      expect(body).to include("a" * limit)
      expect(body).not_to include("a" * (limit + 1))
    end
  end

  describe McpTools::Prompts::CheckMySchedule do
    it "checks the courses, the pairs, and the finals" do
      body = text(described_class)

      expect(body).to include("Call list_terms, then call my_courses with next_term_uid")
      expect_in_order(body, %w[my_courses check_schedule get_course my_finals])
    end
  end

  describe McpTools::Prompts::PlanDegreeProgression do
    it "reads the requirements from the catalog, after the course history" do
      body = text(described_class)

      expect_in_order(body, %w[my_course_history list_programs degree_requirements get_course])
      expect(body).to include("Program: I did not say. Ask me.", "the catalog of the term I started my program in")
    end

    it "asks for the grade of a prerequisite with a min_grade, and names who approves a substitution" do
      expect(text(described_class)).to include("If a prerequisite has a min_grade, ask me for my grade",
                                               "my program director, the dean's office of my school, or both")
    end

    it "asks for the list only when the catalog has no data, and never makes one up" do
      expect(text(described_class)).to include("If degree_requirements has no data for my catalog year",
                                               "Do not make up a list of required courses")
    end

    it "gives the facts the student passed" do
      body = text(described_class, { "program" => "BS Computer Science", "catalog_year" => "2024-2025", "graduation_term" => "Spring 2028" })

      expect(body).to include('Program: "BS Computer Science"', 'Catalog year: "2024-2025"', 'Graduation term: "Spring 2028"')
    end
  end

  describe McpTools::Prompts::FindClassForFreeTime do
    it "reads the busy times before it searches" do
      body = text(described_class, { "subject" => "COMP", "days" => "Tuesday", "times" => "after 13:00" })

      expect(body).to include('Subject: "COMP"', 'Days I am free: "Tuesday"', 'Times I am free: "after 13:00"')
      expect_in_order(body, %w[my_busy_times search_sections check_schedule])
    end
  end
end
