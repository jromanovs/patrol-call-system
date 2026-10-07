require "rails_helper"

# DYN-10: what the script of the board does with the cards marked fresh, run
# by Node with a page made up for the example: it opens on the given cards,
# is refreshed once, and is then kept by Turbo for the way back and left.
RSpec.describe "BoardController" do
  include NodeScript

  def page
    <<~JS
      const heard = {}
      const waits = []
      globalThis.setTimeout = (work, delay) => waits.push({ work, delay })
      const window = { matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }) }
      const document = { documentElement: { dataset: {} }, addEventListener: (name, work) => { heard[name] = work },
                         removeEventListener: (name) => { delete heard[name] } }
    JS
  end

  def lines
    <<~JS
      const made = (marks) => {
        const held = new Set(marks)
        return { held, dataset: { site: "site" }, classList: { contains: (mark) => held.has(mark), remove: (mark) => held.delete(mark),
                                                               toggle: (mark, on) => (on ? held.add(mark) : held.delete(mark)) } }
      }
      const board = new Subject()
      board.element = { querySelector: () => null, querySelectorAll: () => [] }
      board.cardTargets = sent.cards.map(made)
      board.connect()
      const opened = waits.map((wait) => wait.delay)
      heard["turbo:morph"]()
      const refreshed = waits.length
      const listening = Object.keys(heard).sort()
      heard["turbo:before-cache"]?.()
      const kept = board.cardTargets.map((card) => [ ...card.held ])
      board.disconnect()
      console.log(JSON.stringify({ opened, refreshed, listening, kept, left: Object.keys(heard) }))
    JS
  end

  def board(cards) = node(%w[ controllers/fresh_mark.js controllers/board_controller.js ], lines, { cards: }, page:)

  it "waits for a fresh card from the moment it opens, once though the board is refreshed" do
    expect(board([ %w[ critical fresh ], %w[ critical ] ])).to include("opened" => [ 20_000 ], "refreshed" => 1)
  end

  # A page Turbo keeps comes back as it was kept: with the mark on it the
  # card would pulse anew on the way back, however long ago its call came.
  it "takes the mark off its cards before the page is kept for the way back" do
    expect(board([ %w[ critical fresh sos ], %w[ critical ] ])["kept"]).to eq([ %w[ critical sos ], %w[ critical ] ])
  end

  it "listens for a refresh and for the keeping of the page while it is open, and for nothing after it is left", :aggregate_failures do
    seen = board([])

    expect(seen["listening"]).to eq(%w[ turbo:before-cache turbo:morph ])
    expect(seen["left"]).to be_empty
  end
end
