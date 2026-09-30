module ApplicationHelper
  def menu_items
    [
      [ "Board", root_path ],
      [ "Calls", calls_path ],
      [ "Sites", guarded_sites_path ],
      [ "Cars", patrol_cars_path ],
      [ "Map", map_path ]
    ]
  end
end
