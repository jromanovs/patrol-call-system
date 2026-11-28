# The errors of production (solid_errors).
#
# BR-14: its pages are built on ErrorPagesController, so they open after the
# sign-in of the application and to the administrator only, without a
# password of their own. Nothing is sent by e-mail: the gem sends only when
# told to. The occurrences of a resolved error older than 30 days are
# removed, and the error when none is left; the gem looks at every 100th
# occurrence it keeps.
Rails.application.configure do
  config.solid_errors.base_controller_class = "ErrorPagesController"
  config.solid_errors.destroy_after = 30.days
end
