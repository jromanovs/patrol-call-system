require "io/console"

namespace :users do
  desc "Create a user: bin/rails users:create EMAIL=who@example.com NAME=\"Full Name\" [ROLE=administrator]"
  # There is no self-registration: the administrator creates accounts. The
  # password is asked, not passed as an argument, so it stays out of the
  # shell history, the process list and the screen.
  task create: :environment do
    email = ENV.fetch("EMAIL") { abort "Give the address: EMAIL=who@example.com" }
    name = ENV.fetch("NAME") { abort "Give the name: NAME=\"Full Name\"" }
    role = ENV.fetch("ROLE", nil)
    abort "Unknown role #{role}: the roles are #{User.roles.keys.join(', ')}." if role && !User.roles.key?(role)
    abort "A terminal is needed: the password is typed on the keyboard, not piped." unless $stdin.tty?

    password = $stdin.getpass("Password for #{email}: ")
    abort "The passwords do not match." unless password == $stdin.getpass("Once again: ")

    User.create!(email_address: email, name: name, password: password, role: role || User.new.role)
    puts "Created #{email}."
  end
end
