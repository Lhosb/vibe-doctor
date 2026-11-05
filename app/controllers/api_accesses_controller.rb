class ApiAccessesController < ApplicationController
  def edit
    Current.user.regenerate_api_token! if Current.user.api_token.blank?
  end

  def regenerate
    Current.user.regenerate_api_token!
    redirect_to edit_api_access_path, notice: "API token regenerated."
  end
end
