module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || resume_token_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def resume_token_session
      token = bearer_token
      return unless token

      user = User.find_by(api_token: token)
      Current.session = Session.new(user: user) if user
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/, 1]
    end

    def request_authentication
      # A Shortcut sends an Authorization header but often no Accept header, so
      # treat either signal as "this is an API caller" — it can't follow an
      # HTML login redirect either way.
      if request.format.json? || request.authorization.present?
        render json: { error: "unauthorized" }, status: :unauthorized
      else
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_path
      end
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
