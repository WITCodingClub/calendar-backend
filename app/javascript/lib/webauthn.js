// Helpers for the WebAuthn ceremonies. The server sends and expects binary
// values as base64url strings, and the browser API uses ArrayBuffers.

export function base64UrlToBytes(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
  const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "="))
  const buffer = new ArrayBuffer(binary.length)
  const bytes  = new Uint8Array(buffer)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return buffer
}

export function bytesToBase64Url(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

// Asks the browser for an existing passkey, from the server's request options.
export async function getCredential(options) {
  const credential = await navigator.credentials.get({
    publicKey: {
      ...options,
      challenge: base64UrlToBytes(options.challenge),
      allowCredentials: (options.allowCredentials ?? []).map((c) => ({ ...c, id: base64UrlToBytes(c.id) }))
    }
  })

  const assertion = credential.response
  return {
    type: credential.type,
    id: credential.id,
    rawId: bytesToBase64Url(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    response: {
      authenticatorData: bytesToBase64Url(assertion.authenticatorData),
      clientDataJSON: bytesToBase64Url(assertion.clientDataJSON),
      signature: bytesToBase64Url(assertion.signature),
      userHandle: assertion.userHandle ? bytesToBase64Url(assertion.userHandle) : null
    }
  }
}

// Makes a new passkey, from the server's creation options.
export async function createCredential(options) {
  const credential = await navigator.credentials.create({
    publicKey: {
      ...options,
      challenge: base64UrlToBytes(options.challenge),
      user: { ...options.user, id: base64UrlToBytes(options.user.id) },
      excludeCredentials: (options.excludeCredentials ?? []).map((c) => ({ ...c, id: base64UrlToBytes(c.id) }))
    }
  })

  const attestation = credential.response
  return {
    type: credential.type,
    id: credential.id,
    rawId: bytesToBase64Url(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    response: {
      attestationObject: bytesToBase64Url(attestation.attestationObject),
      clientDataJSON: bytesToBase64Url(attestation.clientDataJSON)
    }
  }
}

// True when the user closed the browser prompt. That is a choice, not a fault.
export function isCancelled(error) {
  return error instanceof DOMException && (error.name === "NotAllowedError" || error.name === "AbortError")
}
