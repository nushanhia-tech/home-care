"use client";
import React, {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import {
  Phone,
  PhoneOff,
  Mic,
  MicOff,
  Volume2,
  MessageSquare,
  X,
} from "lucide-react";
import { VoiceEngine } from "../../lib/voice/engine.mjs";
const Context = createContext(null);
export const useVoiceState = () => useContext(Context);
export function VoiceProvider({ me, api, openChat, children }) {
  const [policy, setPolicy] = useState(null);
  const [state, setState] = useState({
      call: null,
      phase: "idle",
      error: "",
      muted: false,
    }),
    [stream, setStream] = useState(null),
    [tick, setTick] = useState(Date.now()),
    [audioBlocked, setAudioBlocked] = useState(false),
    [outputError, setOutputError] = useState(""),
    [outputs, setOutputs] = useState([]);
  const engine = useRef(null),
    audio = useRef(null),
    seen = useRef(new Set());
  useEffect(() => {
    if (!me?.id || me.must_change_password) return;
    api("/operations/config")
      .then(setPolicy)
      .catch(() => setPolicy(null));
    const current = new VoiceEngine(api, setState, setStream);
    engine.current = current;
    let alive = true;
    const incoming = () =>
      api("/voice/incoming")
        .then((calls) => {
          if (!alive) return;
          for (const call of calls) {
            current.incoming(call);
            if (!seen.current.has(call.id)) {
              seen.current.add(call.id);
              if (globalThis.Notification?.permission === "granted")
                new Notification("Local Mate incoming call", {
                  body:
                    call.caller_name + " · booking " + call.booking_reference,
                });
            }
          }
        })
        .catch(() => {});
    incoming();
    const timer = setInterval(incoming, 3000),
      clock = setInterval(() => setTick(Date.now()), 1000);
    const exit = () => {
      const call = current.state.call;
      if (
        call &&
        !["ended", "failed", "missed", "rejected"].includes(call.status)
      )
        fetch("/api/voice/" + call.id + "/action", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ action: "end", reason: "session_ended" }),
          keepalive: true,
        }).catch(() => {});
      current.dispose();
    };
    window.addEventListener("pagehide", exit);
    return () => {
      alive = false;
      clearInterval(timer);
      clearInterval(clock);
      window.removeEventListener("pagehide", exit);
      current.dispose();
      engine.current = null;
    };
  }, [me?.id, me?.must_change_password]);
  useEffect(() => {
    if (!audio.current) return;
    audio.current.srcObject = stream;
    if (stream)
      audio.current
        .play()
        .then(() => setAudioBlocked(false))
        .catch(() => setAudioBlocked(true));
  }, [stream]);
  const call = state.call,
    active =
      call && !["ended", "failed", "missed", "rejected"].includes(call.status),
    other = call
      ? call.caller_id === me?.id
        ? call.callee_name
        : call.caller_name
      : "";
  const duration = call?.connected_at
    ? Math.max(
        0,
        Math.floor(
          ((call.ended_at ? new Date(call.ended_at).getTime() : tick) -
            new Date(call.connected_at).getTime()) /
            1000,
        ),
      )
    : 0;
  const start = async (booking) => {
    if (policy && !policy.calling_enabled)
      throw new Error(
        "Voice calling is currently disabled. Please use in-app chat.",
      );
    if (!engine.current) throw new Error("Sign in to use Local Mate calling.");
    await engine.current.start(booking);
  };
  const output = async () => {
    setOutputError("");
    try {
      if (!audio.current?.setSinkId) {
        setOutputError(
          "Use your device audio controls to select the speaker or headset.",
        );
        return;
      }
      const devices = await navigator.mediaDevices.enumerateDevices();
      setOutputs(devices.filter((d) => d.kind === "audiooutput"));
      if (!devices.some((d) => d.kind === "audiooutput"))
        setOutputError(
          "Select the speaker or headset using your device controls.",
        );
    } catch {
      setOutputError(
        "Audio output selection is unavailable. Use your device audio controls.",
      );
    }
  };
  return (
    <Context.Provider value={{ start, state, policy }}>
      {children}
      <audio ref={audio} autoPlay playsInline />
      {(call || state.error) && (
        <section
          className="voice-panel"
          role="dialog"
          aria-modal="false"
          aria-label="Local Mate voice call"
        >
          <div className="panel-heading">
            <strong>
              <Phone size={18} />
              Local Mate voice call
            </strong>
            {!active && (
              <button
                aria-label="Close call panel"
                onClick={() => engine.current?.dismiss()}
              >
                <X size={18} />
              </button>
            )}
          </div>
          <h3>{other || "In-app voice call"}</h3>
          {call && <small>Booking {call.booking_reference}</small>}
          <p role="status">
            {state.phase === "requesting"
              ? "Requesting microphone permission…"
              : state.phase === "incoming"
                ? "Incoming call"
                : state.phase.replaceAll("_", " ")}
          </p>
          {call?.connected_at && (
            <strong className="call-duration">
              {Math.floor(duration / 60)
                .toString()
                .padStart(2, "0")}
              :{(duration % 60).toString().padStart(2, "0")}
            </strong>
          )}
          {state.error && (
            <p className="form-error" role="alert">
              {state.error}
            </p>
          )}
          <div className="actions">
            {state.phase === "incoming" ? (
              <>
                <button
                  className="button"
                  onClick={() => engine.current?.accept()}
                >
                  <Phone size={16} />
                  Accept
                </button>
                <button
                  className="button secondary"
                  onClick={() => engine.current?.end("reject")}
                >
                  Reject
                </button>
              </>
            ) : active ? (
              <>
                <button
                  className="button secondary"
                  onClick={() => engine.current?.mute()}
                >
                  {state.muted ? <MicOff size={16} /> : <Mic size={16} />}{" "}
                  {state.muted ? "Unmute" : "Mute"}
                </button>
                <button className="button secondary" onClick={output}>
                  <Volume2 size={16} />
                  Speaker / audio output
                </button>
                <button
                  className="button danger-button"
                  onClick={() => engine.current?.end()}
                >
                  <PhoneOff size={16} />
                  End call
                </button>
              </>
            ) : (
              (call || state.booking_id) && (
                <button
                  className="button secondary"
                  onClick={() => start(call?.booking_id || state.booking_id)}
                >
                  Retry call
                </button>
              )
            )}
            {(call || state.booking_id) && (
              <button
                className="button secondary"
                onClick={() => openChat(call?.booking_id || state.booking_id)}
              >
                <MessageSquare size={16} />
                In-app chat
              </button>
            )}
          </div>
          {outputs.length > 0 && (
            <label className="field">
              <span>Audio output device</span>
              <select
                aria-label="Audio output device"
                onChange={async (e) => {
                  try {
                    await audio.current.setSinkId(e.target.value);
                    setOutputError("");
                  } catch {
                    setOutputError(
                      "Could not change the audio output. Use your device controls.",
                    );
                  }
                }}
              >
                {outputs.map((d) => (
                  <option key={d.deviceId} value={d.deviceId}>
                    {d.label || "Audio output"}
                  </option>
                ))}
              </select>
            </label>
          )}
          {outputError && <p>{outputError}</p>}
          {audioBlocked && (
            <button
              className="button secondary"
              onClick={() =>
                audio.current
                  .play()
                  .then(() => setAudioBlocked(false))
                  .catch(() =>
                    setOutputError("Allow audio playback in your browser."),
                  )
              }
            >
              Tap to hear the call
            </button>
          )}
          <small>
            Microphone {state.microphoneOn ? "in use" : "off"}. Internet audio
            only. Local Mate does not record this call.
          </small>
        </section>
      )}
    </Context.Provider>
  );
}
export function CallButton({ booking, me }) {
  const context = useContext(Context),
    [error, setError] = useState("");
  if (
    !booking.provider_id ||
    !booking.accepted_at ||
    (me?.admin && ![booking.provider_id, booking.customer_id].includes(me.id))
  )
    return null;
  return (
    <>
      <button
        className="button secondary"
        disabled={
          !context ||
          !context.policy?.calling_enabled ||
          context.state.phase === "requesting" ||
          (!!context.state.call &&
            !["ended", "failed", "rejected", "missed"].includes(
              context.state.call.status,
            ))
        }
        onClick={async () => {
          setError("");
          try {
            await context.start(booking.id);
          } catch (e) {
            setError(e.message);
          }
        }}
      >
        <Phone size={16} />
        {me.id === booking.provider_id ? "Call Customer" : "Call Provider"}
      </button>
      {error && <p className="form-error">{error}</p>}
    </>
  );
}
export function CallHistory({ api, bookingId }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  useEffect(() => {
    let alive = true;
    api("/voice/history" + (bookingId ? "?booking=" + bookingId : ""))
      .then((v) => {
        if (alive) setItems(v);
      })
      .catch((e) => {
        if (alive) setError(e.message);
      });
    return () => {
      alive = false;
    };
  }, [bookingId]);
  return (
    <div className="panel">
      <h2>Call history</h2>
      {error && <p className="form-error">{error}</p>}
      {items.length ? (
        items.map((c) => (
          <div className="table-row" key={c.id}>
            <div>
              <strong>
                {c.caller_name} → {c.callee_name}
              </strong>
              <small>
                {c.booking_reference} ·{" "}
                {new Date(c.created_at).toLocaleString()}
              </small>
            </div>
            <span>
              {c.status} · {c.duration_seconds}s
            </span>
          </div>
        ))
      ) : (
        <p>No calls recorded in the call history. Audio is never recorded.</p>
      )}
    </div>
  );
}
