module ApplicationHelper
  # The sections of the header. The board is not among them: the system's
  # name opens it. CRW-01: the crew has its own screen only, opened the same
  # way, so it has no sections.
  def menu_items
    return [] unless Current.user && !Current.user.crew?

    [
      [ "Calls", calls_path ],
      [ "Sites", guarded_sites_path ],
      [ "Cars", patrol_cars_path ],
      [ "Statistics", statistics_path ]
    ]
  end

  # USR-09: the theme a page is marked with: the user's, or that of the
  # device where nobody is signed in.
  def page_theme = Current.user&.theme || "system"

  # The page the system's name opens: the board, or the crew's screen.
  def home_page? = current_page?(root_path) || current_page?(crew_path)

  # 4.3: the letters shown in place of a picture of the user.
  def initials(name)
    name.to_s.split(/[\s@._-]+/).reject(&:empty?).first(2).map { |word| word[0] }.join.upcase
  end

  # 4.3: the user's picture, or their initials where there is none. The
  # address of a picture changes with the picture, so that a browser shows a
  # new one at once.
  def avatar(user, **options)
    picture = user.avatar_attachment&.blob_id
    return tag.span(initials(user.name), class: "avatar", **options) unless picture

    image_tag user_picture_path(user, v: picture), alt: "", class: "avatar", **options
  end

  # SRT-02, SRT-03: a column header that orders the list by the column,
  # keeping the search and the filters; a second click turns the direction.
  # The controller of the list names its default column.
  def sort_link(label, column)
    current = params[:sort].presence || default_sort
    shown = params[:direction].presence || default_direction
    direction = current == column && shown == "asc" ? "desc" : "asc"
    link_to label, url_for(request.query_parameters.merge(sort: column, direction:).compact_blank)
  end

  def enum_options(model, attribute)
    model.public_send(attribute.to_s.pluralize).keys.map { |value| [ value.humanize, value ] }
  end
end
