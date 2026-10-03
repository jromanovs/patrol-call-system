import { Controller } from "@hotwired/stimulus"

// One sound output for the page session, as the browser asks.
let audio

// DYN-19: while a crew's SOS is not acknowledged, a signal sounds at once and
// then at every interval. A browser lets a page sound only after a click or a
// key press on it; until then the hint says so, and the first of either
// starts the sound.
export default class extends Controller {
  static targets = [ "strip", "hint" ]
  static values = { interval: { type: Number, default: 5 } }

  connect() {
    if (!this.hasStripTarget) return

    this.unlock = this.unlock.bind(this)
    document.addEventListener("pointerdown", this.unlock)
    document.addEventListener("keydown", this.unlock)
    this.sound()
    this.timer = setInterval(() => this.sound(), this.intervalValue * 1000)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("pointerdown", this.unlock)
    document.removeEventListener("keydown", this.unlock)
  }

  unlock() {
    if (!audio || audio.state === "running") return

    audio.resume().then(() => this.sound())
  }

  // Two short tones; none, and the hint instead, while the sound is held back.
  sound() {
    audio ??= new AudioContext()
    const held = audio.state !== "running"
    this.hintTarget.hidden = !held
    if (held) return

    for (const start of [ 0, 0.25 ]) {
      const tone = audio.createOscillator()
      const volume = audio.createGain()
      tone.frequency.value = 880
      volume.gain.value = 0.2
      tone.connect(volume).connect(audio.destination)
      tone.start(audio.currentTime + start)
      tone.stop(audio.currentTime + start + 0.18)
    }
  }
}
