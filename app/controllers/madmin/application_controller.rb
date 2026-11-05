module Madmin
  class ApplicationController < Madmin::BaseController
    include Authentication
    helper_method :current_user
    before_action :require_admin!

    private

    def current_user
      Current.user
    end

    def require_admin!
      head :forbidden unless current_user&.admin? && Current.session&.persisted?
    end
  end
end
