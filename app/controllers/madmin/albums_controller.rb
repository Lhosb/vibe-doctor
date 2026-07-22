module Madmin
  class AlbumsController < Madmin::ResourceController
    def repair_youtube_link
      @record.repair_youtube_link!(params.require(:youtube_url))
      redirect_to resource.show_path(@record), notice: "YouTube link repaired"
    rescue Album::InvalidYoutubeLinkError, Album::InvalidTransition => e
      redirect_to resource.show_path(@record), alert: e.message
    end
  end
end
