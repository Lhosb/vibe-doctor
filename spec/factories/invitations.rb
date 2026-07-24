FactoryBot.define do
  factory :invitation do
    sequence(:email) { |n| "invitee#{n}@example.com" }
    invited_by { association(:user, admin: true) }
  end
end
