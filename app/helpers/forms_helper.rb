# DSP-04: the message of a wrong field stands above the field, and the field
# names its hint and its message, so a screen reader reads them with it.
module FormsHelper
  def field_error(record, field)
    message = field_messages(record, field).first
    tag.span(message, class: "field-error", id: field_id(record.model_name.param_key, field, :error)) if message
  end

  def field_description(record, field)
    key = record.model_name.param_key
    ids = [ field_id(key, field, :hint) ]
    ids << field_id(key, field, :error) if field_messages(record, field).any?
    ids.join(" ")
  end

  # An error on an association (guarded_site) belongs to the field of its key
  # (guarded_site_id).
  def error_field(record, attribute)
    record.class.reflect_on_association(attribute)&.foreign_key&.to_sym || attribute
  end

  private

  def field_messages(record, field)
    record.errors.select { |error| error_field(record, error.attribute) == field }.map(&:full_message)
  end
end
