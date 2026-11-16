# frozen_string_literal: true

module Api
  # A student's AP, test, and transfer credit (#1020). The extension sends the
  # entries of the LeopardWeb Academic Transcript, and the student can add
  # one by hand. DegreeProgress counts each one as a done course.
  class TransferCreditsController < BaseController
    authenticate_with_token
    include DegreePlanningFlag

    def index
      authorize TransferCredit, :index?

      render_list
    end

    # Body: credits, a list of { code, title, credits, kind }. Replaces the
    # transcript entries. The entries the student added stay.
    def update
      authorize TransferCredit, :replace?
      skipped = AcademicProfiles::TransferCredits.new(current_user).replace_transcript(request.request_parameters["credits"])

      render_list(skipped: skipped.map(&:as_json))
    end

    # Params: code (a course in the catalog), credits and kind (optional).
    def create
      authorize TransferCredit, :create?
      credit = AcademicProfiles::TransferCredits.new(current_user)
                                                .add(code: params[:code], credits: params[:credits], kind: params[:kind])

      render json: TransferCreditSerializer.new(credit).as_json, status: :created
    end

    # Removes a student entry. A transcript entry stays: the next sync would
    # bring it back.
    def destroy
      credit = current_user.transfer_credits.find_by(code: TransferCredit.normalize_value_for(:code, params[:code]))
      return render_error("Transfer credit not found", status: :not_found) if credit.nil?

      authorize credit, :destroy?
      if credit.transcript?
        return render_error("This credit comes from the LeopardWeb transcript and cannot be removed",
                            status: :unprocessable_content, code: "transcript_entry")
      end

      credit.destroy!
      head :no_content
    end

    private

    def render_list(**extra)
      credits = current_user.transfer_credits.order(:code)
      render json: { credits: credits.map { |credit| TransferCreditSerializer.new(credit).as_json }, **extra }
    end
  end
end
