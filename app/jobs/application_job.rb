class ApplicationJob < ActiveJob::Base
  # USR-10: Rails hands a job the language of the request that queued it. A
  # job words a text for its reader, who is someone else, so it begins in
  # English and takes the language of each reader where it words one. The
  # broadcast jobs of Turbo are not of this class and keep that language.
  around_perform { |_job, perform| I18n.with_locale(I18n.default_locale, &perform) }

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
