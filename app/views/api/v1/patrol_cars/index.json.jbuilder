json.count @cars.length
json.patrol_cars @cars, partial: "api/v1/patrol_cars/patrol_car", as: :patrol_car
