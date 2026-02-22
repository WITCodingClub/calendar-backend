# frozen_string_literal: true

class FacultySerializer
  def initialize(faculty)
    @faculty = faculty
  end

  def as_json(*)
    return nil if @faculty.nil?

    {
      pub_id: @faculty.public_id,
      first_name: @faculty.first_name,
      last_name: @faculty.last_name,
      email: @faculty.email,
      rmp_id: @faculty.rmp_id
    }
  end

end
