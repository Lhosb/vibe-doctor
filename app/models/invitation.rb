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

  def status
    return "accepted" if accepted?
    return "revoked" if revoked?
    return "expired" if expired?
    "pending"
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
