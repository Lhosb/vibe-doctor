FactoryBot.define do
  factory :recommendation_event do
    user
    album
    query_text { "warm sunday jazz" }
    candidates_considered { 12 }
    blended_scores { {} }
    rerank_scores { {} }
    final_score { 0.8 }
    explanation { "warm and mellow" }
  end
end
