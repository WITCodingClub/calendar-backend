# CLAUDE.md

Rails 8 app that scrapes WIT course data and syncs it to Google Calendar. Specs use RSpec.

`docs/architecture.md` gives the rules for where code goes. Read it before you add a service, a job, or a controller.

## Admin controllers

- Every action in an `Admin::` controller calls `authorize` or `skip_authorization`. `Admin::ApplicationController` runs `verify_authorized` after each action, and `spec/requests/admin/authorization_spec.rb` requests every admin route to check it.
- Use `skip_authorization` only for an action with no record that another check already guards. Add a one-line comment that says why. `policy_scope` alone does not count: call `authorize` as well.

## API controllers

- Every API controller inherits from `Api::BaseController`. The base requires no token.
- A controller that needs a signed-in user calls `authenticate_with_token` (all actions) or `authenticate_with_token except: [ ... ]` as its first callback.
- `spec/requests/api/authentication_spec.rb` sends a request with no token to every `/api` route. A route must answer 401, unless its action is in `PUBLIC_ACTIONS`. Add a new public action to that list.
- When an extension API path changes, keep the old path in `config/routes/api_legacy.rb`. Remove it when `calendar_api_legacy_requests_total` for that path stays at zero after the extension release that stops calling it.
- Render every API error with `render_error message, status: :not_found` (from `Api::ErrorRendering`). The body is `{ error, code }`. Pass `code:` only when a client needs a code more specific than the status gives.

## Jobs

- A job with `limits_concurrency` names its group with a `CONCURRENCY_GROUP` string constant. Never change that string: Solid Queue puts it in every lock key, and jobs in the queue hold locks under it. `spec/jobs/concurrency_groups_spec.rb` checks this.
- To rename a job class, leave a file at the old path that defines the old name, for example `OldNameJob = Domain::NewNameJob`. Jobs that were in the queue before the deploy still run. Change the enqueue calls and `config/recurring.yml` in the same PR. Remove the alias when `bin/rails jobs:unknown_class_names` on production lists no job with the old name.

## Specs

### Test data

- Build records with factory_bot: `create(:course, term: term)`, `build(:user)`, `create_list(:enrollment, 3)`. Factories live in `spec/factories/`, one file per model.
- Pass only the attributes the example reads or asserts on. The factory fills the rest.
- In factories, use Faker for values no example checks, and `sequence` for unique columns.
- When the same attribute set repeats across specs, add a trait (`create(:user, :unconfirmed)`).
- `spec/factories_spec.rb` builds and saves every factory and trait. A new factory or trait must pass it.
- Migration specs in `spec/migrations/` build rows by hand, because factories follow today's models, not the schema at the migration. Records owned by gems, such as `SolidQueue::Job`, are also built by hand.

### Model specs

- Cover every association, validation, and enum that the model declares with shoulda-matchers one-liners: `it { is_expected.to belong_to(:term) }`.
- `validate_uniqueness_of` needs a saved subject: `subject { create(:course) }`.
- A cross-field or custom validation gets a normal example, with a comment that says why no matcher covers it.

### Outside HTTP

- WebMock blocks every real network request in specs (`spec/support/webmock.rb`). A spec that reaches a real host fails with `WebMock::NetConnectNotAllowedError`.
- Stub at the HTTP boundary with `stub_request`, so the real client code runs: `stub_request(:post, url).to_return(status: 200, body: file_fixture("rate_my_professor/<case>.json").read)`.
- In a service's own spec, stub the HTTP request, not the service's methods. A job spec that only calls a service may stub the service class.
- Put response bodies in `spec/fixtures/files/<service>/`. Write synthetic data in the shape of the real response. The repo is public, so fixtures hold no real names, emails, or tokens.
- The admin layout requests the latest GitHub release on every render. Admin request specs stub that request.

### Fixture leakage

A spec that declares `fixtures :buildings` inserts those rows outside the test transaction, so they stay for the rest of the run. Buildings have unique `name` and `abbreviation` columns. Give buildings in a spec names and abbreviations that `spec/fixtures/buildings.yml` does not use. The building factory uses `FCT` names for this reason. A spec that fails only in the full run usually hits this.

### Running specs

- The test database connection comes from `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`.
- Set `HASHID_SALT` to any value. Without it, boot reads credentials and needs `config/master.key`.
- In a new worktree, run `bin/rails tailwindcss:build` first. Request specs fail without the built CSS.
- The test database needs the `vector` extension (`brew install pgvector`). Without it, `db:test:prepare` fails on the embedding columns. See `docs/embeddings.md`.
- `bin/rails db:test:prepare && bundle exec rspec`
- SimpleCov writes line and branch coverage to `coverage/index.html` after each run. Check it to find untested code.
