# Vibe Doctor — Claude Instructions

These instructions define how code should be written in this Rails app.

## Core architecture rules

- Keep domain/business logic in models when it belongs to the model.
- Use `app/services` only for external integrations (APIs, third-party SDKs, external I/O boundaries).
- Do not create internal service objects for model/domain logic that can live cleanly in a model.
- Keep controllers thin: parameter handling, auth checks, response/redirect rendering.
- Keep jobs orchestration-focused: call model methods and external clients; avoid embedding large domain rule sets in jobs.

## Stack-aware guidance

- Rails 8.1, PostgreSQL, Hotwire (Turbo + Stimulus), Import Maps, Solid Queue, Tailwind, RSpec.
- Prefer Turbo for navigation/partial updates and Stimulus for focused UI behavior.
- Keep Stimulus controllers small, target/action/value-driven, and resilient to Turbo reconnect cycles.

## Ruby and Rails coding standards

- Follow Rails and Ruby conventions first (convention over configuration).
- Write practical object-oriented code: small public APIs, clear responsibilities, cohesive classes.
- Prefer DRY through extraction of meaningful methods, not premature abstraction.
- Prefer guard clauses and intention-revealing method names.
- Use modern Ruby keyword shorthand when appropriate:
  - Prefer `method(user:)` over `method(user: user)` when the local variable name matches.
- Prefer immutable constants for shared static values (`.freeze` where needed).
- Use bang methods (`save!`, `update!`, `find_or_create_by!`) when failure should be explicit.

## Active Record and persistence

- Put validations, state transitions, and invariants on the model that owns them.
- Use explicit custom error classes for invalid state transitions or rule violations.
- Use database constraints/indexes to back application-level uniqueness and integrity checks.
- Use transactions when multiple writes must succeed/fail together.
- Avoid N+1 queries; use `includes`, `preload`, and scope/query composition.

## External integrations

- External API wrappers belong in `app/services` (for example, `DiscogsClient` pattern).
- Keep external clients focused on transport/auth/error normalization.
- Surface external failures clearly; do not silently swallow integration errors.

## Testing expectations

- Add/update specs for behavior changes.
- Prefer model specs for domain rules and invariants.
- Use request/system specs for end-to-end behavior where appropriate.
- Keep tests deterministic; stub external HTTP calls.
- Keep new tests in RSpec style used by this repository.

## Change discipline

- Make minimal, focused changes that align with existing patterns.
- Do not introduce new architecture patterns unless there is a clear, local need.
- If introducing a boundary, document why it is needed in code comments or PR notes.
