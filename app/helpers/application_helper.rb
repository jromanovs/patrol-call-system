module ApplicationHelper
  def menu_items
    # CRW-01: the crew has its own screen only.
    return [ [ "My car", crew_path ] ] if Current.user&.crew?

    [
      [ "Board", root_path ],
      [ "Calls", calls_path ],
      [ "Sites", guarded_sites_path ],
      [ "Cars", patrol_cars_path ],
      [ "Statistics", statistics_path ]
    ] + (Current.user&.administrator? ? [ [ "Users", users_path ], [ "Tracking", tracking_path ] ] : [])
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
