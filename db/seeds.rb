user = User.find_or_initialize_by(email_address: "you@example.com")
user.password = ENV.fetch("SEED_USER_PASSWORD", "changeme123") if user.new_record?
user.admin = true
user.save!
