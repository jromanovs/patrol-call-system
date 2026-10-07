require "rails_helper"

# DYN-10: the mark of a card that has just come in is taken off by the page
# once the server gives it no longer; a card shown again later — its panel
# opened, its tab chosen — would pulse anew with the mark on it. Run by Node
# from the page's own module, with cards and a clock made for the example.
RSpec.describe "FreshMark" do
  include NodeScript

  # The board is refreshed twice, the time passes, and a card is marked again.
  def settled(cards)
    node("controllers/fresh_mark.js", <<~JS, cards:)
      const made = (marks) => { const held = new Set(marks); return { held, classList: { contains: (mark) => held.has(mark), remove: (mark) => held.delete(mark) } } }
      const cards = sent.cards.map(made)
      const settling = new WeakSet()
      const waits = []
      const later = (work, delay) => waits.push({ work, delay })
      settle(cards, settling, later)
      settle(cards, settling, later)
      const asked = waits.map((wait) => wait.delay)
      for (const wait of waits) wait.work()
      const rested = cards.map((card) => [ ...card.held ])
      cards[0].held.add("fresh")
      settle(cards, settling, later)
      console.log(JSON.stringify({ asked, rested, again: waits.length - asked.length, settled: SETTLED }))
    JS
  end

  it "waits once for a fresh card, however often the board is refreshed, and for no other card" do
    seen = settled([ %w[ critical fresh ], %w[ critical ] ])

    expect(seen["asked"]).to eq([ seen["settled"] ])
  end

  it "takes the mark off when the time has passed, and nothing else" do
    expect(settled([ %w[ critical fresh sos ], %w[ critical ] ])["rested"]).to eq([ %w[ critical sos ], %w[ critical ] ])
  end

  it "waits anew for a card that is marked again" do
    expect(settled([ %w[ critical fresh ] ])["again"]).to eq(1)
  end

  # A refresh that arrives while the server still gives the mark would put it
  # back on a card the page had already taken it from.
  it "waits longer than the server gives the mark" do
    expect(settled([ %w[ critical fresh ] ])["settled"]).to be > Call::FRESH.in_milliseconds
  end
end
