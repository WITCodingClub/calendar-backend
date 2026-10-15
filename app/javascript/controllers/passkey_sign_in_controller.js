import { Controller } from "@hotwired/stimulus"
import { getCredential, isCancelled } from "lib/webauthn"

// Signs in with a passkey on the sign-in page. The button stays hidden until
// the browser says it can run the ceremony, so a device with no
// authenticator never sees a button that cannot work.
export default class extends Controller {
  static targets = ["button", "error"]
  static values = { optionsUrl: String, sessionUrl: String }

  connect() {
    if (window.PublicKeyCredential) this.buttonTarget.hidden = false
  }

  async signIn() {
    this.errorTarget.hidden = true
    this.buttonTarget.disabled = true
    try {
      const { handle, options } = await this.post(this.optionsUrlValue)
      const credential = await getCredential(options)
      const result = await this.post(this.sessionUrlValue, { handle, credential })
      window.location.assign(result.redirect_to)
    } catch (error) {
      if (!isCancelled(error)) {
        this.errorTarget.textContent = error.message
        this.errorTarget.hidden = false
      }
      this.buttonTarget.disabled = false
    }
  }

  async post(url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body ?? {})
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || "Could not sign in with that passkey.")
    return data
  }
}
