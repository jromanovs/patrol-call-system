# DYN-09: what the browser checks when a field is left. The rule and the
# message are read from the model's own validators, so the browser and the
# server refuse the same values in the same words.
module FieldChecksHelper
  FORMAT = ActiveModel::Validations::FormatValidator
  LIMITS = ActiveModel::Validations::NumericalityValidator
  # A value no pattern of a field accepts: the validator words its refusal.
  WRONG = "?".freeze

  # The data attributes of the field: a pattern or limits, and the message.
  def field_check(model, attribute)
    format = model.validators_on(attribute).grep(FORMAT).first
    limits = model.validators_on(attribute).grep(LIMITS).first
    if browser_pattern(format) then pattern_check(model, attribute, format)
    elsif limits&.options&.key?(:in) then limits_check(model, attribute, limits)
    else {}
    end
  end

  private

  # A pattern that takes the whole value, written as a browser reads it; a
  # pattern with options of its own is left to the server.
  def browser_pattern(format)
    pattern = format&.options&.dig(:with)
    return unless pattern.is_a?(Regexp) && pattern.options.zero? && pattern.source.match?(/\A\\A.*\\z\z/m)

    pattern.source.sub(/\A\\A/, "^").sub(/\\z\z/, "$")
  end

  def pattern_check(model, attribute, format)
    { check_pattern: browser_pattern(format), check_message: refusal(model, attribute, format, WRONG),
      check_trim: trimmed?(model, attribute), check_upper: capitals?(model, attribute) }.compact_blank
  end

  def limits_check(model, attribute, limits)
    range = limits.options[:in]
    { check_least: range.min, check_most: range.max, check_message: refusal(model, attribute, limits, range.max + 1) }
  end

  # The words the server gives for a value the rule refuses.
  def refusal(model, attribute, rule, wrong)
    record = model.new
    rule.validate_each(record, attribute, wrong)
    record.errors.full_messages_for(attribute).first
  end

  # What the model does to a value before it judges it.
  def trimmed?(model, attribute) = model.normalize_value_for(attribute, " a ") == model.normalize_value_for(attribute, "a")

  def capitals?(model, attribute) = model.normalize_value_for(attribute, "a") == "A"
end
