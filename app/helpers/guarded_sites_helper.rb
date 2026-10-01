module GuardedSitesHelper
  # SRT-02: a column header that orders the list by the column, keeping the
  # search and the filters; a second click turns the direction.
  def sort_link(label, column)
    current = params[:sort].presence || "name"
    direction = current == column && params[:direction] != "desc" ? "desc" : "asc"
    link_to label, guarded_sites_path(request.query_parameters.merge(sort: column, direction:))
  end

  def site_enum_options(attribute)
    GuardedSite.public_send(attribute.to_s.pluralize).keys.map { |value| [ value.humanize, value ] }
  end
end
