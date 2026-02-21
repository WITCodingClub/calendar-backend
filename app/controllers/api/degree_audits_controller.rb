# frozen_string_literal: true

module Api
  # API endpoints for degree audit sync and retrieval
  class DegreeAuditsController < ApiController
    include ApiResponseFormatter

    before_action :authenticate_user!
    before_action :set_user

    # POST /api/users/me/degree_audit/sync
    # Sync degree audit from LeopardWeb HTML
    def sync
      # Validate required parameters
      validate_sync_params!

      result = DegreeAuditSyncService.sync(
        user: @user,
        html: params[:html],
        degree_program_id: params[:degree_program_id],
        term_id: params[:term_id]
      )

      # Authorize the created snapshot (use create? since we're creating/syncing)
      authorize result[:snapshot], :create?

      success_response(
        data: {
          snapshot_id: result[:snapshot].id,
          duplicate: result[:duplicate],
          evaluated_at: result[:snapshot].evaluated_at,
          summary: {
            total_credits_required: result[:snapshot].total_credits_required,
            total_credits_completed: result[:snapshot].total_credits_completed,
            overall_gpa: result[:snapshot].overall_gpa,
            evaluation_met: result[:snapshot].evaluation_met
          }
        },
        message: result[:message]
      )
    rescue DegreeAuditParserService::StructureError => e
      error_response(
        error: "Failed to parse degree audit HTML. The structure may have changed.",
        code: ApiErrorCodes::PARSE_ERROR,
        status: :unprocessable_entity
      )
    rescue DegreeAuditSyncService::ParseTimeout => e
      error_response(
        error: e.message,
        code: ApiErrorCodes::PARSE_ERROR,
        status: :request_timeout
      )
    rescue DegreeAuditSyncService::ConcurrentSyncError => e
      error_response(
        error: e.message,
        code: ApiErrorCodes::CONCURRENT_SYNC,
        status: :conflict
      )
    rescue ActionController::ParameterMissing => e
      validation_error("Missing required parameter: #{e.param}")
    end

    # GET /api/users/me/degree_audit
    # Get current degree audit (most recent)
    def show
      # Validate required parameters
      validate_program_param!

      snapshot = @user.degree_evaluation_snapshots
                      .where(degree_program_id: params[:degree_program_id])
                      .order(evaluated_at: :desc)
                      .first

      if snapshot
        authorize snapshot, :show?
        success_response(
          data: {
            id: snapshot.id,
            degree_program_id: snapshot.degree_program_id,
            evaluated_at: snapshot.evaluated_at,
            parsed_data: snapshot.parsed_data,
            summary: {
              total_credits_required: snapshot.total_credits_required,
              total_credits_completed: snapshot.total_credits_completed,
              overall_gpa: snapshot.overall_gpa,
              evaluation_met: snapshot.evaluation_met
            }
          }
        )
      else
        error_response(
          error: "No degree audit found for this program",
          code: ApiErrorCodes::NO_AUDIT_AVAILABLE,
          status: :not_found
        )
      end
    end

    # GET /api/users/me/degree_audit/history
    # Get all historical degree audits
    def history
      # Validate required parameters
      validate_program_param!

      # Authorize index action
      authorize DegreeEvaluationSnapshot, :index?

      # Add pagination
      page = params[:page]&.to_i || 1
      per_page = [params[:per_page]&.to_i || 20, 100].min # Max 100 per page

      snapshots = @user.degree_evaluation_snapshots
                       .where(degree_program_id: params[:degree_program_id])
                       .order(evaluated_at: :desc)
                       .page(page)
                       .per(per_page)

      success_response(
        data: {
          snapshots: snapshots.map { |snapshot|
            {
              id: snapshot.id,
              degree_program_id: snapshot.degree_program_id,
              evaluated_at: snapshot.evaluated_at,
              summary: {
                total_credits_required: snapshot.total_credits_required,
                total_credits_completed: snapshot.total_credits_completed,
                overall_gpa: snapshot.overall_gpa,
                evaluation_met: snapshot.evaluation_met
              }
            }
          },
          pagination: {
            current_page: snapshots.current_page,
            total_pages: snapshots.total_pages,
            total_count: snapshots.total_count,
            per_page: per_page
          }
        }
      )
    end

    private

    def set_user
      @user = current_user
    end

    # Validate sync parameters
    def validate_sync_params!
      params.require(:html)
      params.require(:degree_program_id)
      params.require(:term_id)

      # Validate HTML is not empty
      if params[:html].blank?
        raise ActionController::BadRequest, "HTML content cannot be empty"
      end

      # Validate IDs are positive integers
      unless params[:degree_program_id].to_i.positive?
        raise ActionController::BadRequest, "Invalid degree_program_id"
      end

      return if params[:term_id].to_i.positive?

      raise ActionController::BadRequest, "Invalid term_id"

    end

    # Validate program parameter
    def validate_program_param!
      params.require(:degree_program_id)

      return if params[:degree_program_id].to_i.positive?

      raise ActionController::BadRequest, "Invalid degree_program_id"

    end

  end
end
