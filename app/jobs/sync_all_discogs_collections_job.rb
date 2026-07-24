class SyncAllDiscogsCollectionsJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(discogs_token: nil).find_each do |user|
      SyncDiscogsCollectionJob.perform_later(user)
    end
  end
end
