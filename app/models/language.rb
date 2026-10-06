# USR-10: the languages the pages can be drawn in.
module Language
  # A browser names a few languages. The header is a stranger's to write, so
  # of a longer list only the first ones are read.
  READ = 10

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
    languages = offered
    wanted = header.to_s.split(",", READ + 1).first(READ).filter_map do |part|
      tag, weight = part.strip.split(/\s*;\s*q=/i, 2)
      quality = weight ? Float(weight, exception: false) : 1.0
      # Two letters and then the country or the end: "rue" is no Russian.
      [ tag.to_s[/\A([a-z]{2})(?:-|\z)/i, 1]&.downcase, quality ] if quality&.positive?
    end
    wanted.sort_by.with_index { |(_, quality), place| [ -quality, place ] }.map(&:first).find { |code| languages.include?(code) }
  end
end
