# frozen_string_literal: true

module Dashboard
  # The student's plan of study as a prerequisite graph, by semester (#449).
  # A click on a course focuses it and shows what comes before it and what it
  # unlocks (#448). GET /api/user/curriculum_graph sends the same data.
  class CurriculaController < Dashboard::ApplicationController
    def show
      authorize current_user, :show?

      @graph = build_graph(focus: params[:focus].presence)
    rescue AcademicProfiles::DegreeProgress::NoProgramError
      @graph = nil
    end

    private

    # An unknown focus code keeps the graph and shows the error. An unknown
    # program or plan shows only the error.
    def build_graph(focus:)
      AcademicProfiles::CurriculumGraph.new(current_user, program: params[:program].presence,
                                                          plan: params[:plan].presence, focus: focus).call
    rescue Catalog::FilterError => e
      @error = e.message
      focus ? build_graph(focus: nil) : nil
    end
  end
end
