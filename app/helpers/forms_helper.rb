# DSP-04: the message of a wrong field stands above the field, and the field
# names its hint and its message, so a screen reader reads them with it.
module FormsHelper
  def field_error(record, attribute)
    message = record.errors.full_messages_for(attribute).first
    tag.span(message, class: "field-error", id: field_id(record.model_name.param_key, attribute, :error)) if message
  end

  def field_description(record, attribute)
    key = record.model_name.param_key
    ids = [ field_id(key, attribute, :hint) ]
    ids << field_id(key, attribute, :error) if record.errors.include?(attribute)
    ids.join(" ")
  end
end
