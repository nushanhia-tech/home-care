const terminal = new Set(["ended", "rejected", "missed", "failed"]);
export class VoiceEngine {
  constructor(api, emit, onStream) {
    this.api = api;
    this.emit = emit;
    this.onStream = onStream;
    this.state = {
      call: null,
      phase: "idle",
      error: "",
      muted: false,
      microphoneOn: false,
    };
    this.generation = 0;
    this.pendingCandidates = [];
    this.after = 0;
    this.disposed = false;
  }
  publish(patch) {
    this.state = { ...this.state, ...patch };
    if (!this.disposed) this.emit({ ...this.state });
  }
  async microphone() {
    if (!globalThis.navigator?.mediaDevices?.getUserMedia)
      throw new Error("Microphone access needs HTTPS and a supported browser.");
    try {
      return await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true },
        video: false,
      });
    } catch (e) {
      throw new Error(
        e.name === "NotAllowedError"
          ? "Microphone permission was denied. Allow microphone access to make a call."
          : "The microphone is unavailable. Check your device and try again.",
      );
    }
  }
  async start(booking) {
    if (
      (this.state.call && !terminal.has(this.state.call.status)) ||
      this.state.phase === "requesting"
    )
      throw new Error("Finish the current call first.");
    const token = ++this.generation;
    this.publish({
      call: null,
      booking_id: booking,
      phase: "requesting",
      error: "",
      muted: false,
    });
    try {
      const stream = await this.microphone();
      if (token !== this.generation || this.disposed) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      this.local = stream;
      this.publish({ microphoneOn: true });
      const result = await this.api("/voice/start", { booking_id: booking });
      if (token !== this.generation || this.disposed) {
        await this.api("/voice/" + result.call.id + "/action", {
          action: "end",
        }).catch(() => {});
        return;
      }
      this.publish({ call: result.call, phase: "ringing" });
      this.peer(result.ice, token);
      this.monitor();
      const offer = await this.pc.createOffer();
      await this.pc.setLocalDescription(offer);
      await this.signal("offer", this.pc.localDescription.toJSON());
    } catch (e) {
      if (token === this.generation) await this.fail(e.message);
    }
  }
  incoming(call) {
    if (
      this.disposed ||
      (this.state.call && !terminal.has(this.state.call.status))
    )
      return;
    this.generation++;
    this.publish({ call, phase: "incoming", error: "", muted: false });
    this.monitor();
  }
  async accept() {
    if (this.state.phase !== "incoming") return;
    const token = this.generation;
    this.publish({ phase: "requesting", error: "" });
    try {
      const stream = await this.microphone();
      if (token !== this.generation || this.disposed) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      this.local = stream;
      this.publish({ microphoneOn: true });
      const result = await this.api(
        "/voice/" + this.state.call.id + "/action",
        { action: "accept" },
      );
      if (token !== this.generation || this.disposed) return;
      if (terminal.has(result.call.status))
        throw new Error("This call has ended.");
      this.publish({ call: result.call, phase: "connecting" });
      this.peer(result.ice, token);
      await this.pull();
      this.connectTimeout = setTimeout(() => {
        if (this.state.phase !== "active")
          void this.fail(
            "The connection could not be established. Retry or use in-app messaging.",
          );
      }, 30000);
    } catch (e) {
      if (token === this.generation) await this.fail(e.message);
    }
  }
  peer(ice, token) {
    this.pc = new RTCPeerConnection({
      iceServers: ice.iceServers,
      iceTransportPolicy: ice.iceTransportPolicy || "all",
    });
    this.after = 0;
    this.pendingCandidates = [];
    for (const track of this.local.getAudioTracks())
      this.pc.addTrack(track, this.local);
    this.pc.onicecandidate = (event) => {
      if (event.candidate && token === this.generation)
        void this.signal("candidate", event.candidate.toJSON()).catch((e) =>
          this.fail(e.message),
        );
    };
    this.pc.ontrack = (event) => {
      if (token === this.generation)
        this.onStream(event.streams[0] || new MediaStream([event.track]));
    };
    this.pc.onconnectionstatechange = () => {
      if (token !== this.generation || !this.pc) return;
      const state = this.pc.connectionState;
      if (state === "connected") {
        clearTimeout(this.connectTimeout);
        clearTimeout(this.disconnectTimeout);
        this.publish({ phase: "active" });
        void this.api("/voice/" + this.state.call.id + "/action", {
          action: "connected",
        })
          .then((r) => {
            if (token === this.generation) this.publish({ call: r.call });
          })
          .catch((e) => this.fail(e.message));
      } else if (state === "failed")
        void this.fail(
          "The call connection failed. Retry or use in-app messaging.",
        );
      else if (state === "disconnected") {
        this.publish({ phase: "reconnecting" });
        clearTimeout(this.disconnectTimeout);
        this.disconnectTimeout = setTimeout(() => {
          if (this.pc?.connectionState === "disconnected")
            void this.fail(
              "The internet connection was interrupted. Please retry or use chat.",
            );
        }, 12000);
      }
    };
  }
  async signal(kind, payload) {
    const id = this.state.call?.id;
    if (!id || this.disposed) return;
    return this.api("/voice/" + id + "/signal", { kind, payload });
  }
  monitor() {
    clearInterval(this.pollTimer);
    clearInterval(this.heartbeatTimer);
    this.pollTimer = setInterval(() => void this.pull(), 1500);
    this.heartbeatTimer = setInterval(() => {
      if (this.state.call && this.state.phase !== "incoming")
        void this.api("/voice/" + this.state.call.id + "/heartbeat", {})
          .then((c) => this.updateCall(c))
          .catch((e) => this.fail(e.message));
    }, 10000);
  }
  updateCall(call) {
    if (!call || call.id !== this.state.call?.id) return;
    if (terminal.has(call.status)) {
      this.teardown();
      this.publish({ call, phase: call.status });
      return;
    }
    this.publish({
      call,
      ...(call.status === "accepted" && this.state.phase === "ringing"
        ? { phase: "connecting" }
        : {}),
    });
  }
  async pull() {
    if (
      this.pulling ||
      !this.state.call ||
      terminal.has(this.state.call.status) ||
      this.disposed
    )
      return;
    this.pulling = true;
    const token = this.generation,
      id = this.state.call.id;
    try {
      const call = await this.api("/voice/" + id);
      if (token !== this.generation) return;
      this.updateCall(call);
      if (!this.pc || terminal.has(call.status)) return;
      const signals = await this.api(
        "/voice/" + id + "/signals?after=" + this.after,
      );
      for (const s of signals) {
        if (token !== this.generation || !this.pc) return;
        this.after = Math.max(this.after, Number(s.id));
        if (s.kind === "candidate") {
          if (this.pc.remoteDescription)
            await this.pc.addIceCandidate(s.payload);
          else this.pendingCandidates.push(s.payload);
        } else if (s.kind === "offer") {
          await this.pc.setRemoteDescription(s.payload);
          for (const c of this.pendingCandidates.splice(0))
            await this.pc.addIceCandidate(c);
          const answer = await this.pc.createAnswer();
          await this.pc.setLocalDescription(answer);
          await this.signal("answer", this.pc.localDescription.toJSON());
        } else if (s.kind === "answer") {
          await this.pc.setRemoteDescription(s.payload);
          for (const c of this.pendingCandidates.splice(0))
            await this.pc.addIceCandidate(c);
        }
      }
    } catch (e) {
      if (token === this.generation) await this.fail(e.message);
    } finally {
      this.pulling = false;
    }
  }
  mute() {
    if (!this.local) return;
    const muted = !this.state.muted;
    this.local.getAudioTracks().forEach((t) => {
      t.enabled = !muted;
    });
    this.publish({ muted });
  }
  teardown() {
    clearInterval(this.pollTimer);
    clearInterval(this.heartbeatTimer);
    clearTimeout(this.connectTimeout);
    clearTimeout(this.disconnectTimeout);
    if (this.pc) {
      this.pc.ontrack = null;
      this.pc.onicecandidate = null;
      this.pc.onconnectionstatechange = null;
      this.pc.close();
      this.pc = null;
    }
    this.local?.getTracks().forEach((t) => t.stop());
    this.local = null;
    this.state = { ...this.state, microphoneOn: false };
    this.onStream(null);
  }
  async end(action = "end") {
    const call = this.state.call;
    ++this.generation;
    this.teardown();
    this.publish({
      phase: action === "reject" ? "rejected" : "ended",
      call: call
        ? { ...call, status: action === "reject" ? "rejected" : "ended" }
        : null,
    });
    if (call && !terminal.has(call.status))
      try {
        const result = await this.api("/voice/" + call.id + "/action", {
          action,
          reason: "session_ended",
        });
        this.publish({ call: result.call });
      } catch {}
  }
  async fail(message) {
    const call = this.state.call;
    ++this.generation;
    this.teardown();
    this.publish({
      phase: "failed",
      error: message || "Calling is unavailable. Please use in-app messaging.",
      call: call ? { ...call, status: "failed" } : null,
    });
    if (call && !terminal.has(call.status))
      await this.api("/voice/" + call.id + "/action", {
        action: "failed",
      }).catch(() => {});
  }
  dismiss() {
    this.publish({ call: null, phase: "idle", error: "" });
  }
  dispose() {
    void this.end();
    this.disposed = true;
  }
}
