class VibeMapController < ApplicationController
  def index
    render_vibe_map(Current.user.collection_items, user: Current.user)
  end

  def global
    return head :forbidden unless current_user&.admin?

    render_vibe_map(CollectionItem.all)
  end

  private

  def render_vibe_map(collection_items, user: nil)
    builder = Albums::VibeMapBuilder.new(collection_items, user:)
    @dots = builder.dots
    @dots_json = builder.dots_json
  end
end
