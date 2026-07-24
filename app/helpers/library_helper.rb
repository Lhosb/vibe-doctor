module LibraryHelper
  STATUS_BADGE_CLASSES = {
    "pending" => "bg-gray-100 text-gray-700",
    "matching_audio" => "bg-yellow-100 text-yellow-700",
    "extracting_features" => "bg-yellow-100 text-yellow-700",
    "grounded" => "bg-green-100 text-green-700",
    "failed" => "bg-red-100 text-red-700"
  }.freeze

  def status_badge_class(enrichment_status)
    STATUS_BADGE_CLASSES.fetch(enrichment_status, "bg-gray-100 text-gray-700")
  end
end
