module BoardHelper
  # DSP-03: the panels as the user left them. The browser keeps each choice
  # in a cookie, so the page is drawn that way from the start; only these
  # values are taken.
  CHOICES = { "callsPanel" => "minimized", "carsPanel" => "minimized", "legendPanel" => "minimized",
              "legendPhone" => "open", "sheet" => "lowered", "sheetTab" => "cars" }.freeze

  # The choices as data attributes of the html element, which a refresh of
  # the page leaves alone.
  def board_choices
    CHOICES.filter_map { |choice, value| [ choice.underscore, value ] if cookies["board_#{choice}"] == value }.to_h
  end

  def panel_open?(panel) = !board_choices.key?("#{panel}_panel")

  # DYN-03: minutes inside a sentence, which the waiting controller counts on
  # from the time given.
  def counted_minutes(count, since)
    tag.span(t("common.minutes", count:), data: { waiting_target: "minutes", received_at: since.iso8601 })
  end
end
