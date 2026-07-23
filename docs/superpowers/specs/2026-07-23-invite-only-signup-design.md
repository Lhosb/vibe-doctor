# Invite-Only Signup — Design

## Context

Today, user accounts can only be created by an admin, manually, through the Madmin
admin panel (`Madmin::UserResource`). There is no public signup path, no
`RegistrationsController`, and no route for creating an account other than an admin
directly editing the `users` table via Madmin.

Authentication is Rails' built-in `has_secure_password` (bcrypt), with a custom
database-backed `Session` model and an `Authentication` concern
(`app/controllers/concerns/authentication.rb`) included in `ApplicationController`.
Password reset already exists (`PasswordsController`, `PasswordsMailer`), using a
token in the URL (`resources :passwords, param: :token`) and Rails' built-in
`has_secure_password` token generation.

This design introduces **invite-only signup**: an admin invites a specific email
address from Madmin, the invitee receives an email with a signup link, and clicking
it lets them set a password and create their account. There is no open registration
endpoint — an account can only be created in response to an admin-issued invitation
(or, for the very first admin, via `db/seeds.rb`).

## Goals

- Admins can invite a user by email from Madmin.
- The invitee receives an email with a link to complete signup.
- Invitations expire (7 days) and can be revoked or resent by an admin.
- No account is created until the invitee actually completes the signup form.
- The very first admin account is bootstrapped via `db/seeds.rb`, since no admin
  exists yet to send an invite.
- Follow existing conventions exactly: plain Rails resources (no Devise), ERB +
  Tailwind views matching `sessions/new.html.erb` / `passwords/edit.html.erb`,
  rate-limited public actions, request/system/model specs matching the existing
  test structure.

## Non-goals

- Open/self-service registration (anyone can sign up without an invite).
- Email domain allowlisting.
- Inviting someone directly as an admin (admin promotion happens afterward via the
  existing Madmin `User` resource, same as today).

## Data model

### `Invitation` (new model/table)

| column         | type      | notes                                          |
|----------------|-----------|-------------------------------------------------|
| `email`        | string    | not null                                        |
| `token`        | string    | not null, unique — via `has_secure_token :token` |
| `invited_by_id`| references `users` | admin who created the invitation       |
| `expires_at`   | datetime  | not null, defaults to 7 days from creation      |
| `accepted_at`  | datetime  | nullable                                        |
| `revoked_at`   | datetime  | nullable                                        |

Model helper methods: `expired?`, `revoked?`, `accepted?`, `usable?` (none of the
other three true) — plain timestamp checks, no state machine, consistent with how
`PasswordsController` already treats token expiry as a simple time comparison.

Validations:
- `email` presence + format.
- No other *usable* invitation already exists for the same email (prevents
  duplicate active invites).
- `email` does not already belong to an existing `User`.

`User` gets **no new columns**. It continues to mean exactly what it means today —
a real, authenticatable account — and is only created when the invitee completes
the signup form.

## Bootstrap: the first admin

Since invites can only be sent by an existing admin, `db/seeds.rb` creates the
first admin directly, bypassing the invitation system entirely:

```ruby
User.find_or_create_by!(email_address: ENV.fetch("ADMIN_EMAIL")) do |u|
  u.password = ENV.fetch("ADMIN_PASSWORD")
  u.admin = true
end
```

`find_or_create_by!` only sets attributes when creating a new record, so re-running
seeds never resets an existing admin's password. Credentials come from ENV, not
hardcoded into the committed file.

### Deploy/build integration

Migrations currently run in `bin/docker-entrypoint` (line 5) via `./bin/rails
db:prepare`, invoked whenever the container boots the Rails server. `db:prepare`
only auto-seeds when it creates a brand-new database — it does **not** reseed an
existing database on every deploy. Since `db/seeds.rb`'s admin bootstrap is
idempotent, add an explicit `./bin/rails db:seed` call immediately after
`db:prepare` in `bin/docker-entrypoint`, so the admin bootstrap check always runs on
every boot, regardless of whether the database is new or pre-existing.

## Components & data flow

### Routes

```ruby
resources :registrations, param: :token, only: [:edit, :update]
```

Mirrors `PasswordsController`'s token-based `edit`/`update` pattern exactly:
- `GET /registrations/:token/edit` → show the signup form.
- `PATCH /registrations/:token` → create the account.

There is no `new`/`create` for registrations — the invitee never initiates an
invitation; only an admin does, from Madmin.

### Madmin (admin side)

New `Madmin::InvitationResource`, generated-CRUD style like the existing
`Madmin::UserResource`:

- **Create**: admin enters an email. `before_create` generates `token` (via
  `has_secure_token`), sets `expires_at` (7 days out) and `invited_by` (`Current.user`),
  then sends the invite email.
- **Member actions**: `Resend` (regenerate token + expiry, resend email) and
  `Revoke` (set `revoked_at`).
- Index displays computed status (pending / accepted / expired / revoked) per
  invitation.

### Mailer

`InvitationsMailer#invite_email(invitation)` — same shape as `PasswordsMailer`,
links to `edit_registration_path(invitation.token)`.

### Public side — `RegistrationsController`

- `before_action` loads the `Invitation` by token.
  - Missing token → redirect to login, flash: "This invitation link is invalid."
  - `expired?` → redirect to login, flash: "This invitation has expired. Ask an
    admin to resend it."
  - `revoked?` → redirect to login, same generic invalid-link message (does not
    reveal it was specifically revoked).
  - `accepted?` (link reused after signup) → redirect to login, flash: "This
    invitation has already been used. Please log in."
- `edit`: renders the signup form. Email is shown read-only (sourced from the
  invitation, not user-editable); fields for `password` / `password_confirmation`.
- `update`: builds `User.new(email_address: invitation.email, password: ...,
  password_confirmation: ...)`.
  - On save: sets `invitation.accepted_at = Time.current`, calls
    `start_new_session_for(user)` (the same `Authentication` concern helper
    `SessionsController#create` uses) to auto-log-in the new user, redirects to
    root.
  - On failure: re-renders the form with errors, same pattern as
    `SessionsController#create`'s failure path.
  - Rate-limited the same way as `SessionsController#create` and
    `PasswordsController#create` (10 attempts / 3 minutes).

### View

`app/views/registrations/edit.html.erb` — same Tailwind form styling as
`sessions/new.html.erb` / `passwords/edit.html.erb`.

## Error handling / edge cases

- Invalid/unknown token → redirect to login, generic invalid-link flash.
- Expired invitation → redirect to login, expiry-specific flash suggesting the
  admin resend it.
- Revoked invitation → redirect to login, generic invalid-link flash (no detail
  leaked).
- Already-accepted invitation reused → redirect to login, "already used" flash.
- Duplicate active invite for the same email → `Invitation` validation blocks
  creation; Madmin surfaces the validation error.
- Invite for an email that already has a `User` → validation blocks creation.
- Abuse of the signup endpoint → rate-limited (10/3min) on `update`.

## Testing

Following the existing structure (`spec/requests`, `spec/system`, `spec/models`,
FactoryBot):

- **`spec/factories/invitations.rb`** — sequenced email, `invited_by` association
  to an admin user.
- **`spec/models/invitation_spec.rb`** — email presence/format validation, no
  duplicate usable invite per email, can't invite an email that's already a
  `User`, token uniqueness, and the `expired?`/`revoked?`/`accepted?`/`usable?`
  predicate methods.
- **`spec/requests/registrations_spec.rb`**:
  - `GET edit` with valid / invalid / expired / revoked / already-accepted token →
    correct render vs. redirect+flash for each case.
  - `PATCH update` with valid token + matching passwords → creates the `User`,
    sets `accepted_at`, signs the user in, redirects to root.
  - `PATCH update` with mismatched password confirmation → re-renders with
    errors, no `User` created.
  - Rate-limit behavior on repeated `update` attempts.
- **`spec/system/registration_spec.rb`** — full Capybara flow matching
  `authentication_spec.rb`: visit the invite link, fill in password fields,
  submit, land on an authenticated page.
- **Madmin invitation resource** — full request-spec coverage (unlike the
  existing, untested `Madmin::UserResource`) for:
  - Creating an invitation (including the duplicate-email and
    already-a-user validation failures).
  - `Resend` (token/expiry regenerated, email re-sent).
  - `Revoke` (sets `revoked_at`, revoked invitation becomes unusable).
