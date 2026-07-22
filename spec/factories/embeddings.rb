FactoryBot.define do
  factory :embedding do
    album
    sonic { Array.new(1536, 0.1) }
    emotional { Array.new(1536, 0.1) }
    situational { Array.new(1536, 0.1) }
    era { Array.new(1536, 0.1) }
  end
end
