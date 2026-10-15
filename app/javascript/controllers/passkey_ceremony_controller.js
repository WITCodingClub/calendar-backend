import { Controller } from "@hotwired/stimulus"
import { createCredential, getCredential, isCancelled } from "lib/webauthn"

// Runs a passkey ceremony for the extension, then hands the result back to
// it. The ceremony runs on this site so the origin the browser reports is
// this site's, not the extension's. See Auth::PasskeyCeremoniesController.
export default class extends Controller {
  static targets = ["status", "retry"]
  static values = { mode: String, redirectUri: String, state: String, handoff: String, nickname: String }

  connect() {
    this.run()
  }

  async run() {
    this.retryTarget.hidden = true
    try {
      await (this.modeValue === "register" ? this.register() : this.signIn())
    } catch (error) {
      // A dismissed prompt is a choice, not a fault. Tell the extension either
      // way so it stops waiting rather than hanging on an open tab.
      if (isCancelled(error)) {
        this.say("Cancelled.")
        this.handBack({ error: "cancelled" })
        return
      }
      console.error(error)
      this.say(error.message || "Something went wrong.")
      this.retryTarget.hidden = false
    }
  }

  async register() {
    const { handle, options } = await this.post("/api/user/passkeys/registration_options", { handoff: this.handoffValue })
    const credential = await createCredential(options)
    // The handoff authenticates this call too, and is spent here.
    await this.post("/api/user/passkeys", { handle, handoff: this.handoffValue, nickname: this.nicknameValue, credential })

    this.say("Passkey added. Returning to the extension…")
    this.handBack({ ok: "1" })
  }

  async signIn() {
    const { handle, options } = await this.post("/api/user/passkeys/authentication_options")
    const credential = await getCredential(options)
    const { code } = await this.post("/api/user/passkeys/authenticate", { handle, handoff: true, credential })

    this.say("Signed in. Returning to the extension…")
    this.handBack({ code })
  }

  say(message) {
    this.statusTarget.textContent = message
  }

  // Hands the result back to the extension. Only ever a single-use code, never
  // a session token, because this lands in browser history.
  handBack(params) {
    const target = new URL(this.redirectUriValue)
    if (this.stateValue) target.searchParams.set("state", this.stateValue)
    for (const [key, value] of Object.entries(params)) target.searchParams.set(key, value)
    window.location.replace(target.toString())
  }

  async post(path, body) {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body ?? {})
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`)
    return data
  }
}
