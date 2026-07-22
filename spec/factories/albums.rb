FactoryBot.define do
  factory :album do
    sequence(:master_id) { |n| n }
    title { "Sample Album" }
    artists { ["Sample Artist"] }
    genres { ["Jazz"] }
    styles { [] }
    year { 2020 }

    trait :grounded do
      enrichment_status { "grounded" }
    end
  end
end
