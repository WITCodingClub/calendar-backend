# frozen_string_literal: true

module Admin
  # Finds a record by its public id ("usr_...") from the admin search box. The
  # prefix comes from each model's set_public_id_prefix.
  class PublicIdLookupController < Admin::ApplicationController
    PATHS = {
      Term    => :admin_term_path,
      Course  => :admin_course_path,
      Faculty => :admin_faculty_path,
      User    => :admin_user_path
    }.freeze

    MODELS_BY_PREFIX = PATHS.keys.index_by(&:public_id_prefix).freeze

    def lookup
      authorize :admin, :access_admin_endpoints?

      record, error = find_record
      return render(json: { error: error[:message] }, status: error[:status]) if error

      render json: {
        public_id:    record.public_id,
        type:         record.class.name,
        display_name: display_name(record),
        path:         send(PATHS.fetch(record.class), record)
      }
    end

    def redirect
      authorize :admin, :access_admin_endpoints?

      record, error = find_record
      return redirect_to(admin_root_path, alert: error[:message]) if error

      redirect_to send(PATHS.fetch(record.class), record)
    end

    private

    # [record, nil], or [nil, { message:, status: }].
    def find_record
      public_id = params[:public_id].to_s.strip.downcase
      return [ nil, { message: "Public ID is required", status: :bad_request } ] if public_id.blank?

      prefix = public_id.split("_").first
      model  = MODELS_BY_PREFIX[prefix]
      return [ nil, { message: "Unknown public ID prefix: #{prefix}", status: :not_found } ] unless model

      record = model.find_by_public_id(public_id)
      return [ nil, { message: "Record not found for public ID: #{public_id}", status: :not_found } ] unless record

      [ record, nil ]
    end

    def display_name(record)
      case record
      when Term    then record.name
      when Faculty then record.full_name
      when Course  then "#{record.code} - #{record.title}"
      when User    then record.email || "User ##{record.id}"
      end
    end
  end
end
