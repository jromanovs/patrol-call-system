// DYN-10: the server marks the card of a critical call as fresh for 15
// seconds from its registration, and a refresh of the board after that takes
// the mark off. Where no refresh comes the mark is taken off here: with it
// left on, a card shown again later — its panel opened, its tab chosen —
// would pulse anew. The wait is longer than the server gives the mark, so no
// refresh puts it back on a card it was taken from.
export const SETTLED = 20000

export function settle(cards, settling, later = setTimeout) {
  for (const card of cards) {
    if (!card.classList.contains("fresh") || settling.has(card)) continue
    settling.add(card)
    later(() => {
      card.classList.remove("fresh")
      settling.delete(card)
    }, SETTLED)
  }
}
