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
