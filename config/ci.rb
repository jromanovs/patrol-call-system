# Run using bin/ci. The GitHub workflow runs the same command.

CI.run do
  step "Setup", "bin/setup --skip-server"

  # Text files, Ruby and HAML: the same checks as before every commit.
  step "Style: text, Ruby, HAML", "git ls-files -z | xargs -0 .githooks/pre-commit"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Stylesheets: Sass and PostCSS build", "bin/rails css:build"
  step "Tests", "bundle exec rspec"
end
