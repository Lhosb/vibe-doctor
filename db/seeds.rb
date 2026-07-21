User.find_or_create_by!(email_address: "you@example.com") do |user|
  user.password = ENV.fetch("SEED_USER_PASSWORD", "changeme123")
end
