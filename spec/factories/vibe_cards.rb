FactoryBot.define do
  factory :vibe_card do
    album
    time_of_day { [ "evening" ] }
    activities { [ "cooking dinner", "winding down" ] }
    energy_arc { "Starts mellow and builds gradually." }
    texture { "Warm analog synths over a steady groove." }
    seasons { [ "autumn" ] }
    prose { "A record built for slow evenings, leaning into warm, deliberate arrangements." }
  end
end
