# frozen_string_literal: true

module McpTools
  # Wentworth's registration rules, as the server instructions, the prompts,
  # the tool descriptions and the advisory name them. Each text builds its own
  # sentences from these parts, so a rule changes in one place. The rules come
  # from the Registrar's notice for Spring 2027.
  module Policy
    # Who gives a registration override.
    OVERRIDE_OFFICE = "the dean's office of the school that offers the course"

    # Where a student finds the registration time.
    TIME_TICKET = "time ticket, in myWentworth under Prepare for Registration"

    # Who needs a RAC before registering, and who gives it.
    RAC = "Registration Alternate PIN (RAC)"
    RAC_STUDENTS = "first-year students, sophomores, and students on academic probation, continued probation, " \
                   "or academic dismissal"
    RAC_GIVER = "primary advisor"

    # Who confirms a course plan.
    PLAN_CONFIRMERS = "program director and academic advisor"
  end
end
