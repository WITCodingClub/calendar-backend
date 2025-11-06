module Api
  class MiscController < ApplicationController

    def get_current_terms
      #   returns the current term, and the next term

      current_term = Term.current
      next_term = Term.next

      render json: {
        current_term: {
          name: current_term.name,
          id: current_term.uid
        },
        next_term: {
          name: next_term.name,
          id: next_term.uid
        }
      }, status: :ok

    end

  end
end