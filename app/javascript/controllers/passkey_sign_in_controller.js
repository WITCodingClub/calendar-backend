import { Controller } from "@hotwired/stimulus"
import { getCredential, isCancelled, postJson } from "lib/webauthn"

const FAILED = "Could not sign in with that passkey."

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
      const { handle, options } = await postJson(this.optionsUrlValue, {}, FAILED)
      const credential = await getCredential(options)
      const result = await postJson(this.sessionUrlValue, { handle, credential }, FAILED)
      window.location.assign(result.redirect_to)
    } catch (error) {
      if (!isCancelled(error)) {
        this.errorTarget.textContent = error.message
        this.errorTarget.hidden = false
      }
      this.buttonTarget.disabled = false
    }
  }
}
