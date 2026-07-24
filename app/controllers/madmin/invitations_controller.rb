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
