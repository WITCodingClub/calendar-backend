# frozen_string_literal: true

# Response of POST /api/process_courses/batch: the user's calendar links and
# one result for each term in the request, in request order.
class CourseBatchResultSerializer
  def initialize(user, results)
    @user = user
    @results = results
  end

  def as_json(*)
    {
      user_pub: @user.public_id,
      ics_url:  @user.cal_url_with_extension,
      terms:    @results.map { |result| term_json(result) }
    }
  end

  private

  def term_json(result)
    json = { term: result.term, status: result.status }
    json[:course_count] = result.course_count unless result.course_count.nil?
    json[:error] = result.error if result.error
    json
  end
end
