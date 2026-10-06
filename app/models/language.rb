# USR-10: the languages the pages can be drawn in.
module Language
  # A language is offered once its own file gives its name; the standard
  # texts of Rails alone do not make one. Asked without a fallback, so that
  # the English name is not taken for the name of another language.
  def self.offered
    I18n.available_locales.map(&:to_s).select { |code| I18n.t("language.name", locale: code, default: nil, fallback: false) }
  end

  # The name of a language in itself.
  def self.name_of(code) = I18n.t("language.name", locale: code)

  # The offered language a browser asks for first, by the weights of its
  # Accept-Language header; none when it asks for no language of the system.
  def self.asked(header)
    wanted = header.to_s.split(",").filter_map do |part|
      tag, weight = part.strip.split(";q=", 2)
      quality = weight ? Float(weight, exception: false) : 1.0
      [ tag.to_s[/\A[a-z]{2}/i]&.downcase, quality ] if quality&.positive?
    end
    wanted.sort_by.with_index { |(_, quality), place| [ -quality, place ] }.map(&:first).find { |code| offered.include?(code) }
  end
end
