# Invite-Only Signup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin invite a specific email address from Madmin and have that person set a password and create their own account, with no open public registration endpoint.

**Architecture:** A new `Invitation` model (email, token, expiry, invited-by, accepted/revoked timestamps) tracks the whole lifecycle. Madmin gets a new resource for admins to create invitations and copy the resulting signup link (no email sending yet). A public `RegistrationsController`, keyed by the invitation's token, lets the invitee set a password and creates the `User` only at that point — mirroring the existing `PasswordsController`'s token-based `edit`/`update` pattern exactly.

**Tech Stack:** Rails 8.1.3, `has_secure_password` / `has_secure_token` (no Devise), Madmin 2.3 for the admin panel, RSpec + FactoryBot + Capybara for tests, ERB + Tailwind for views.

**Full design spec:** `docs/superpowers/specs/2026-07-23-invite-only-signup-design.md`

## Global Constraints

- No Devise, no new gems — use Rails' built-in `has_secure_password` / `has_secure_token`, matching every existing auth file in this app.
- Public, state-changing controller actions must be rate-limited the same way as `SessionsController#create` / `PasswordsController#create`: `rate_limit to: 10, within: 3.minutes`.
- Views follow the existing ERB + Tailwind form conventions in `app/views/sessions/new.html.erb` and `app/views/passwords/*.html.erb` — same input classes, same flash-message markup.
- Madmin resources/controllers only ever run as an already-authenticated admin (`Madmin::ApplicationController` already enforces `current_user&.admin?`) — no new authorization code needed.
- No automated invite emails in this pass — Madmin displays the signup link for the admin to copy/share manually (outgoing mail isn't configured in this app yet; see the spec's Future work section).
- `db/seeds.rb` already creates the bootstrap admin (`User.find_or_initialize_by(email_address: "you@example.com")` with `ENV.fetch("SEED_USER_PASSWORD", "changeme123")` and `admin = true`) — do not modify it. The only remaining gap is that it's never invoked during deploy.

---

## Task 1: `Invitation` model

**Files:**
- Create: `db/migrate/<timestamp>_create_invitations.rb`
- Create: `app/models/invitation.rb`
- Create: `spec/factories/invitations.rb`
- Test: `spec/models/invitation_spec.rb`

**Interfaces:**
- Produces: `Invitation` model with columns `email:string`, `token:string` (unique), `invited_by_id` (references `users`), `expires_at:datetime`, `accepted_at:datetime`, `revoked_at:datetime`. Instance methods `expired?`, `revoked?`, `accepted?`, `usable?`, `regenerate_link!`. Factory `:invitation` (requires `invited_by:`).

- [ ] **Step 1: Generate and write the migration**

Run: `bin/rails generate migration CreateInvitations`

This creates `db/migrate/<timestamp>_create_invitations.rb` with today's timestamp. Replace its contents with:

```ruby
class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.string :email, null: false
      t.string :token, null: false
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, :email
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `db/schema.rb` now includes a `create_table "invitations"` block with the columns above, and `ActiveRecord::Schema[8.1]` version bumped to the new migration's timestamp.

- [ ] **Step 3: Write the factory**

Create `spec/factories/invitations.rb`:

```ruby
FactoryBot.define do
  factory :invitation do
    sequence(:email) { |n| "invitee#{n}@example.com" }
    invited_by { association(:user, admin: true) }
  end
end
```

- [ ] **Step 4: Write the failing model spec**

Create `spec/models/invitation_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Invitation, type: :model do
  it "is valid with an email and an inviting admin" do
    expect(build(:invitation)).to be_valid
  end

  it "requires an email" do
    invitation = build(:invitation, email: nil)
    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("can't be blank")
  end

  it "requires a validly formatted email" do
    invitation = build(:invitation, email: "not-an-email")
    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("is invalid")
  end

  it "rejects an email that already belongs to a user" do
    create(:user, email_address: "listener@example.com")
    invitation = build(:invitation, email: "listener@example.com")

    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("already has an account")
  end

  it "rejects a duplicate usable invitation for the same email" do
    create(:invitation, email: "friend@example.com")
    duplicate = build(:invitation, email: "friend@example.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to include("already has a pending invitation")
  end

  it "allows a new invitation for an email whose prior invitation was revoked" do
    create(:invitation, email: "friend@example.com", revoked_at: Time.current)
    new_invitation = build(:invitation, email: "friend@example.com")

    expect(new_invitation).to be_valid
  end

  it "generates a token on creation" do
    expect(create(:invitation).token).to be_present
  end

  it "defaults to expiring 7 days from creation" do
    expect(create(:invitation).expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  describe "#usable?" do
    it "is usable when pending, unexpired, and unrevoked" do
      expect(create(:invitation)).to be_usable
    end

    it "is not usable when expired" do
      invitation = create(:invitation, expires_at: 1.minute.ago)
      expect(invitation).to be_expired
      expect(invitation).not_to be_usable
    end

    it "is not usable when revoked" do
      invitation = create(:invitation, revoked_at: Time.current)
      expect(invitation).to be_revoked
      expect(invitation).not_to be_usable
    end

    it "is not usable when already accepted" do
      invitation = create(:invitation, accepted_at: Time.current)
      expect(invitation).to be_accepted
      expect(invitation).not_to be_usable
    end
  end

  describe "#regenerate_link!" do
    it "issues a new token and resets the expiration so an expired invitation becomes usable again" do
      invitation = create(:invitation, expires_at: 1.minute.ago)
      old_token = invitation.token

      invitation.regenerate_link!

      expect(invitation.token).not_to eq(old_token)
      expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
      expect(invitation).to be_usable
    end
  end
end
```

- [ ] **Step 5: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/invitation_spec.rb`
Expected: FAIL with `uninitialized constant Invitation`

- [ ] **Step 6: Implement the model**

Create `app/models/invitation.rb`:

```ruby
class Invitation < ApplicationRecord
  EXPIRATION_PERIOD = 7.days

  has_secure_token :token

  belongs_to :invited_by, class_name: "User"

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :email_not_already_a_user, on: :create
  validate :no_other_usable_invitation_for_email, on: :create

  before_validation :set_expiration, on: :create

  scope :usable, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def accepted?
    accepted_at.present?
  end

  def usable?
    !expired? && !revoked? && !accepted?
  end

  def regenerate_link!
    update!(token: self.class.generate_unique_secure_token, expires_at: EXPIRATION_PERIOD.from_now)
  end

  private
    def set_expiration
      self.expires_at ||= EXPIRATION_PERIOD.from_now
    end

    def email_not_already_a_user
      errors.add(:email, "already has an account") if User.exists?(email_address: email)
    end

    def no_other_usable_invitation_for_email
      errors.add(:email, "already has a pending invitation") if Invitation.usable.where(email: email).exists?
    end
end
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/invitation_spec.rb`
Expected: PASS (14 examples, 0 failures)

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/invitation.rb spec/factories/invitations.rb spec/models/invitation_spec.rb
git commit -m "Add Invitation model for invite-only signup"
```

---

## Task 2: Public signup (`RegistrationsController`)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/registrations_controller.rb`
- Create: `app/views/registrations/edit.html.erb`
- Test: `spec/requests/registrations_spec.rb`
- Test: `spec/system/registration_spec.rb`

**Interfaces:**
- Consumes: `Invitation` model and `#usable?`/`#expired?`/`#revoked?`/`#accepted?` from Task 1. `start_new_session_for(user)` and `after_authentication_url` from `app/controllers/concerns/authentication.rb:37,41`.
- Produces: routes `edit_registration_path(token)` / `registration_path(token)`, used by Task 3's Madmin resource to display the signup link.

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, add this line directly after `resources :passwords, param: :token` (line 7):

```ruby
  resources :registrations, param: :token, only: [:edit, :update]
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/registrations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /registrations/:token/edit" do
    it "renders the signup form for a usable invitation" do
      invitation = create(:invitation, email: "friend@example.com")

      get edit_registration_path(invitation.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("friend@example.com")
    end

    it "redirects with an alert for an unknown token" do
      get edit_registration_path("does-not-exist")

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("invalid")
    end

    it "redirects with an alert for an expired invitation" do
      invitation = create(:invitation, expires_at: 1.minute.ago)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("expired")
    end

    it "redirects for a revoked invitation" do
      invitation = create(:invitation, revoked_at: Time.current)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
    end

    it "redirects with an alert for an already-accepted invitation" do
      invitation = create(:invitation, accepted_at: Time.current)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("already been used")
    end
  end

  describe "PATCH /registrations/:token" do
    it "creates the user, marks the invitation accepted, and signs the user in" do
      invitation = create(:invitation, email: "friend@example.com")

      patch registration_path(invitation.token), params: { password: "s3cret-pass", password_confirmation: "s3cret-pass" }

      expect(response).to redirect_to(root_path)
      user = User.find_by(email_address: "friend@example.com")
      expect(user).to be_present
      expect(user.authenticate("s3cret-pass")).to eq(user)
      expect(invitation.reload).to be_accepted

      get library_path
      expect(response).to have_http_status(:ok)
    end

    it "does not create a user when the passwords do not match" do
      invitation = create(:invitation, email: "friend@example.com")

      expect {
        patch registration_path(invitation.token), params: { password: "s3cret-pass", password_confirmation: "different" }
      }.not_to change(User, :count)

      expect(response).to redirect_to(edit_registration_path(invitation.token))
      expect(invitation.reload).not_to be_accepted
    end
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/registrations_spec.rb`
Expected: FAIL with a routing error (`uninitialized constant RegistrationsController` or `No route matches`)

- [ ] **Step 4: Implement the controller**

Create `app/controllers/registrations_controller.rb`:

```ruby
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_invitation
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def edit
  end

  def update
    @user = User.new(
      email_address: @invitation.email,
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )

    if @user.save
      @invitation.update!(accepted_at: Time.current)
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome! Your account has been created."
    else
      redirect_to edit_registration_path(@invitation.token), alert: "Passwords did not match."
    end
  end

  private
    def set_invitation
      @invitation = Invitation.find_by(token: params[:token])

      if @invitation.nil?
        redirect_to new_session_path, alert: "This invitation link is invalid."
      elsif @invitation.expired?
        redirect_to new_session_path, alert: "This invitation has expired. Ask an admin for a new link."
      elsif @invitation.revoked?
        redirect_to new_session_path, alert: "This invitation link is invalid."
      elsif @invitation.accepted?
        redirect_to new_session_path, alert: "This invitation has already been used. Please log in."
      end
    end
end
```

- [ ] **Step 5: Write the view**

Create `app/views/registrations/edit.html.erb`:

```erb
<div class="mx-auto md:w-2/3 w-full">
  <% if alert = flash[:alert] %>
    <p class="py-2 px-3 bg-red-50 mb-5 text-red-500 font-medium rounded-lg inline-block" id="alert"><%= alert %></p>
  <% end %>

  <h1 class="font-bold text-4xl">Create your account</h1>

  <%= form_with url: registration_path(@invitation.token), method: :patch, class: "contents" do |form| %>
    <div class="my-5">
      <%= text_field_tag :email_address, @invitation.email, disabled: true, class: "block shadow-sm rounded-md border border-gray-400 bg-gray-100 px-3 py-2 mt-2 w-full" %>
    </div>

    <div class="my-5">
      <%= form.password_field :password, required: true, autocomplete: "new-password", placeholder: "Choose a password", maxlength: 72, class: "block shadow-sm rounded-md border border-gray-400 focus:outline-blue-600 px-3 py-2 mt-2 w-full" %>
    </div>

    <div class="my-5">
      <%= form.password_field :password_confirmation, required: true, autocomplete: "new-password", placeholder: "Repeat password", maxlength: 72, class: "block shadow-sm rounded-md border border-gray-400 focus:outline-blue-600 px-3 py-2 mt-2 w-full" %>
    </div>

    <div class="inline">
      <%= form.submit "Create account", class: "w-full sm:w-auto text-center rounded-md px-3.5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white inline-block font-medium cursor-pointer" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/registrations_spec.rb`
Expected: PASS (7 examples, 0 failures)

- [ ] **Step 7: Write the failing system spec**

Create `spec/system/registration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Registration", type: :system do
  it "lets an invited user set a password and creates their account" do
    invitation = create(:invitation, email: "friend@example.com")

    visit edit_registration_path(invitation.token)

    fill_in "Choose a password", with: "s3cret-pass"
    fill_in "Repeat password", with: "s3cret-pass"
    click_button "Create account"

    expect(page).to have_content("Library")
    expect(page).to have_content("friend@example.com")
  end
end
```

- [ ] **Step 8: Run the system spec**

Run: `bundle exec rspec spec/system/registration_spec.rb`
Expected: PASS (1 example, 0 failures). (This should already pass after Step 4-5 above; it's here to confirm the full browser flow, not just the request-level behavior.)

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/registrations_controller.rb app/views/registrations spec/requests/registrations_spec.rb spec/system/registration_spec.rb
git commit -m "Add public invite-acceptance signup flow"
```

---

## Task 3: Madmin invitation management

**Files:**
- Modify: `config/routes/madmin.rb`
- Create: `app/madmin/resources/invitation_resource.rb`
- Create: `app/controllers/madmin/invitations_controller.rb`
- Test: `spec/requests/madmin_invitations_spec.rb`

**Interfaces:**
- Consumes: `Invitation` model/validations (Task 1), `edit_registration_path`/`edit_registration_url` route helpers (Task 2), `current_user` helper method from `app/controllers/madmin/application_controller.rb:9`.

- [ ] **Step 1: Add the Madmin routes**

In `config/routes/madmin.rb`, add this block directly after `resources :users` (so the file reads `resources :users` then the new block then `resources :vibe_cards`):

```ruby
  resources :invitations do
    post :regenerate_link, on: :member
    post :revoke, on: :member
  end
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/madmin_invitations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Madmin: invitations", type: :request do
  let(:admin) { create(:user, admin: true) }

  before { sign_in_as(admin) }

  describe "creating an invitation" do
    it "creates an invitation for the given email and records the inviting admin" do
      post "/admin/invitations", params: { invitation: { email: "friend@example.com" } }

      invitation = Invitation.last
      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.email).to eq("friend@example.com")
      expect(invitation.invited_by).to eq(admin)
    end

    it "rejects an email that already belongs to a user" do
      create(:user, email_address: "listener@example.com")

      expect {
        post "/admin/invitations", params: { invitation: { email: "listener@example.com" } }
      }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a duplicate usable invitation for the same email" do
      create(:invitation, invited_by: admin, email: "friend@example.com")

      expect {
        post "/admin/invitations", params: { invitation: { email: "friend@example.com" } }
      }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows a copyable signup link on the invitation's show page" do
      invitation = create(:invitation, invited_by: admin, email: "friend@example.com")

      get "/admin/invitations/#{invitation.id}"

      expect(response.body).to include(edit_registration_path(invitation.token))
    end
  end

  describe "regenerating a link" do
    it "issues a new token and extends the expiration" do
      invitation = create(:invitation, invited_by: admin, expires_at: 1.minute.ago)
      old_token = invitation.token

      post "/admin/invitations/#{invitation.id}/regenerate_link"

      invitation.reload
      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.token).not_to eq(old_token)
      expect(invitation).to be_usable
    end
  end

  describe "revoking an invitation" do
    it "marks the invitation revoked so it can no longer be used" do
      invitation = create(:invitation, invited_by: admin)

      post "/admin/invitations/#{invitation.id}/revoke"

      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.reload).to be_revoked
    end
  end

  it "forbids a non-admin from managing invitations" do
    sign_in_as(create(:user, admin: false))

    get "/admin/invitations"

    expect(response).to have_http_status(:forbidden)
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/madmin_invitations_spec.rb`
Expected: FAIL (`uninitialized constant InvitationResource` or routing error)

- [ ] **Step 4: Implement the Madmin resource**

Create `app/madmin/resources/invitation_resource.rb`:

```ruby
class InvitationResource < Madmin::Resource
  attribute :id, form: false
  attribute :email
  attribute :token, form: false
  attribute :expires_at, form: false
  attribute :accepted_at, form: false
  attribute :revoked_at, form: false
  attribute :created_at, form: false
  attribute :updated_at, form: false

  # Associations
  attribute :invited_by, form: false

  member_action do |record|
    text_field_tag :signup_link, edit_registration_url(record.token, host: request.base_url), readonly: true, class: "form-input", onclick: "this.select()"
  end

  member_action do |record|
    button_to "Regenerate Link", regenerate_link_madmin_invitation_path(record), method: :post, class: "btn btn-secondary"
  end

  member_action do |record|
    button_to "Revoke", revoke_madmin_invitation_path(record), method: :post, class: "btn btn-danger" unless record.revoked?
  end
end
```

- [ ] **Step 5: Implement the Madmin controller**

Create `app/controllers/madmin/invitations_controller.rb`:

```ruby
module Madmin
  class InvitationsController < Madmin::ResourceController
    def create
      @record = Invitation.new(resource_params)
      @record.invited_by = current_user

      if @record.save
        redirect_to resource.show_path(@record), notice: "Invitation created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def regenerate_link
      @record.regenerate_link!
      redirect_to resource.show_path(@record), notice: "Invite link regenerated."
    end

    def revoke
      @record.update!(revoked_at: Time.current)
      redirect_to resource.show_path(@record), notice: "Invitation revoked."
    end
  end
end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/madmin_invitations_spec.rb`
Expected: PASS (6 examples, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add config/routes/madmin.rb app/madmin/resources/invitation_resource.rb app/controllers/madmin/invitations_controller.rb spec/requests/madmin_invitations_spec.rb
git commit -m "Add Madmin invitation management (create, regenerate link, revoke)"
```

---

## Task 4: Run the admin bootstrap seed on every deploy

**Files:**
- Modify: `bin/docker-entrypoint`

**Interfaces:**
- Consumes: the existing `db/seeds.rb` (unmodified — see Global Constraints).

- [ ] **Step 1: Confirm the current entrypoint content**

`bin/docker-entrypoint` currently reads:

```bash
#!/bin/bash -e

# If running the rails server then create or migrate existing database
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

- [ ] **Step 2: Add the seed call**

Edit `bin/docker-entrypoint` so the conditional block reads:

```bash
#!/bin/bash -e

# If running the rails server then create or migrate existing database
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
  ./bin/rails db:seed
fi

exec "${@}"
```

- [ ] **Step 3: Verify seeding is idempotent locally**

Run: `bin/rails db:seed && bin/rails db:seed`
Expected: both runs exit `0` with no errors, and `User.find_by(email_address: "you@example.com")` still has only one record (`bin/rails runner 'puts User.where(email_address: "you@example.com").count'` prints `1`).

- [ ] **Step 4: Commit**

```bash
git add bin/docker-entrypoint
git commit -m "Run db:seed on every boot so the bootstrap admin always exists"
```
