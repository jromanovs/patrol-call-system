# The active-calls board, the home page (DSP-03).
class BoardController < ApplicationController
  def index
    @calls = Call.on_board.includes(guarded_site: :address)
    @cars = PatrolCar.on_panel.to_a
  end
end
