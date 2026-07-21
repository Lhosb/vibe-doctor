FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "listener#{n}@example.com" }
    password { "s3cret-pass" }
  end
end
