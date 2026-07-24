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
