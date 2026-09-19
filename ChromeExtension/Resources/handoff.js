(() => {
  const endpoint = "ws://127.0.0.1:10027";
  const protocol = "sdm.handoff.v1";
  const encoder = new TextEncoder();
  const base64 = (bytes) => {
    let value = "";
    for (let offset = 0; offset < bytes.length; offset += 8192) {
      value += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
    }
    return btoa(value);
  };
  const bytes = (text) => Uint8Array.from(atob(text), (value) => value.charCodeAt(0));

  async function send(payload, tab) {
    if (tab?.id === undefined) return { accepted: false };
    const id = crypto.randomUUID();
    const rawKey = crypto.getRandomValues(new Uint8Array(32));
    const key = await crypto.subtle.importKey("raw", rawKey, "AES-GCM", false, ["encrypt", "decrypt"]);
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const plain = encoder.encode(JSON.stringify(payload));
    if (plain.length > 96 * 1024) return { accepted: false };
    const encrypted = new Uint8Array(await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce, additionalData: encoder.encode(id) }, key, plain));
    const sealed = new Uint8Array(nonce.length + encrypted.length);
    sealed.set(nonce); sealed.set(encrypted, nonce.length);
    // Only the random key travels through OS activation. The private payload
    // travels separately, encrypted; a process squatting on the port cannot read it.
    const callback = globalThis.SDMDownloadSupport.callbackURL("handoff", {
      id, key: base64(rawKey),
    }, "chrome");
    await chrome.tabs.update(tab.id, { url: callback });
    const deadline = Date.now() + 30_000;
    while (Date.now() < deadline) {
      try {
        return await new Promise((resolve, reject) => {
          const socket = new WebSocket(endpoint, protocol);
          const timer = setTimeout(() => { socket.close(); reject(new Error("Timed out")); }, 2500);
          function close() { clearTimeout(timer); socket.close(); }
          socket.onopen = () => socket.send(JSON.stringify({ id, sealed: base64(sealed) }));
          socket.onerror = () => { close(); reject(new Error("Unavailable")); };
          socket.onclose = () => { clearTimeout(timer); reject(new Error("Closed")); };
          socket.onmessage = async (event) => {
            try {
              const data = bytes(event.data);
              const response = await crypto.subtle.decrypt({ name: "AES-GCM", iv: data.slice(0, 12),
                additionalData: encoder.encode(id) }, key, data.slice(12));
              const result = JSON.parse(new TextDecoder().decode(response));
              close(); resolve({ accepted: result.accepted === true });
            } catch { close(); reject(new Error("Invalid receipt")); }
          };
        });
      } catch { await new Promise((resolve) => setTimeout(resolve, 250)); }
    }
    return { accepted: false };
  }
  globalThis.SDMChromeHandoff = Object.freeze({ send });
})();
