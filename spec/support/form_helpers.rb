# DSP-04: every field has a label above it and a hint with an example of the
# format. A hint is an element of class "hint" that the field names in
# aria-describedby, so a screen reader reads it together with the field.
module FormHelpers
  FIELDS = "input:not([type=hidden]):not([type=submit]), select, textarea".freeze

  def fields_without_label_or_hint(document)
    document.css(FIELDS).reject { |field| labelled?(document, field) && hinted?(document, field) }
            .map { |field| field["name"] }
  end

  private

  def labelled?(document, field)
    document.at_css("label[for='#{field['id']}']").present?
  end

  def hinted?(document, field)
    field["aria-describedby"].to_s.split.any? { |id| document.at_css("##{id}.hint").present? }
  end
end

RSpec.configure do |config|
  config.include FormHelpers, type: :request
end
