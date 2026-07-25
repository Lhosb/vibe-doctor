class ApiAccessesController < ApplicationController
  def edit
  end

  def regenerate
    Current.user.regenerate_api_token!
    redirect_to edit_api_access_path, notice: "API token regenerated."
  end
end
