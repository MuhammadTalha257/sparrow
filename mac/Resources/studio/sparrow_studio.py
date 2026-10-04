#!/usr/bin/env python3
"""Sparrow Studio voice — a small local server around OmniVoice (k2-fsa, Apache-2.0).

Runs only on this Mac (127.0.0.1), offline once the model is downloaded.

GET  /health                      → {"ready":bool,"loading":bool,"device":str,"voice":str,"error":str}
POST /speak  {"text","lang","speed"}           → audio/wav (24 kHz). Repeated phrases come from a cache instantly.
POST /voice  {"instruct","lang"}               → designs a new Sparrow voice from a description and keeps it
POST /voice  {"ref_audio":path,"ref_text"}     → clones the voice in a recording (10–20 s is best)

One fixed voice is kept (a voice-clone prompt), so Sparrow always sounds like the same person.
"""
import hashlib
import io
import json
import os
import sys
import threading
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOME = os.path.expanduser("~/Library/Application Support/Sparrow/studio")
CACHE = os.path.join(HOME, "cache")
VOICE_PT = os.path.join(HOME, "voice.pt")
VOICE_JSON = os.path.join(HOME, "voice.json")
PORT = int(os.environ.get("SPARROW_STUDIO_PORT", "47321"))
os.makedirs(CACHE, exist_ok=True)

DEFAULT_INSTRUCT = "female, young adult, moderate pitch, british accent"
REF_SENTENCE = {
    "en": "Hello, I'm Sparrow. I'll keep an eye on your day, remind you about meetings, and help you get things done.",
    "ur": "السلام علیکم، میں سپیرو ہوں۔ میں آپ کے دن کا خیال رکھوں گی اور آپ کو میٹنگز یاد دلاؤں گی۔",
    "hi": "नमस्ते, मैं स्पैरो हूँ। मैं आपके दिन का ध्यान रखूँगी और आपको मीटिंग्स याद दिलाऊँगी।",
}

state = {"ready": False, "loading": True, "device": "", "voice": "", "error": ""}
model = None
prompt = None
lock = threading.Lock()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def gen_kwargs():
    # Fewer steps on a CPU keeps replies quick; the GPU on Apple silicon can afford full quality.
    return {"num_step": 32 if state["device"] == "mps" else 16, "guidance_scale": 2.0}


def lang_code(lang, text):
    if any("਀" <= c <= "੿" for c in text):
        return "pa"                     # Gurmukhi Punjabi
    if lang in ("pa", "pnb"):
        return "pnb" if any("؀" <= c <= "ۿ" for c in text) else "pa"
    if lang in ("ur", "hi", "ar", "en"):
        return lang
    return None


def wav_bytes(audio, sr):
    import soundfile as sf
    buf = io.BytesIO()
    sf.write(buf, audio, sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def make_voice_from_design(instruct, lang="en"):
    """Design a voice once, then keep it as a clone prompt so every reply sounds like the same person."""
    global prompt
    import torch
    from omnivoice import VoiceClonePrompt  # noqa: F401
    text = REF_SENTENCE.get(lang, REF_SENTENCE["en"])
    audio = model.generate(text=text, language=lang, instruct=instruct, **gen_kwargs())[0]
    p = model.create_voice_clone_prompt(ref_audio=(torch.from_numpy(audio), model.sampling_rate), ref_text=text)
    p.save(VOICE_PT)
    with open(os.path.join(HOME, "voice-sample.wav"), "wb") as f:
        f.write(wav_bytes(audio, model.sampling_rate))
    prompt = p
    save_voice_info({"kind": "design", "instruct": instruct})


def make_voice_from_recording(path, ref_text):
    global prompt
    p = model.create_voice_clone_prompt(ref_audio=path, ref_text=ref_text or None)
    p.save(VOICE_PT)
    prompt = p
    save_voice_info({"kind": "clone", "file": os.path.basename(path)})


def save_voice_info(info):
    info["id"] = hashlib.sha1(json.dumps(info, sort_keys=True).encode()).hexdigest()[:10]
    with open(VOICE_JSON, "w") as f:
        json.dump(info, f)
    state["voice"] = info["id"]


def load():
    global model, prompt
    try:
        import torch
        from omnivoice import OmniVoice, VoiceClonePrompt
        from omnivoice.utils.common import get_best_device
        dev = get_best_device()
        if dev == "cuda":
            dev = "cuda:0"
        state["device"] = dev
        dtype = torch.float16 if dev != "cpu" else torch.float32
        torch.set_num_threads(max(2, (os.cpu_count() or 4) - 1))
        log(f"Loading OmniVoice on {dev} …")
        model = OmniVoice.from_pretrained(os.environ.get("SPARROW_STUDIO_MODEL", "k2-fsa/OmniVoice"), device_map=dev, dtype=dtype)
        if os.path.exists(VOICE_PT):
            prompt = VoiceClonePrompt.load(VOICE_PT)
            try:
                state["voice"] = json.load(open(VOICE_JSON)).get("id", "voice")
            except Exception:
                state["voice"] = "voice"
        else:
            log("Designing the default Sparrow voice …")
            make_voice_from_design(DEFAULT_INSTRUCT)
        state["ready"] = True
        log("Sparrow Studio voice is ready.")
    except Exception as e:
        state["error"] = f"{type(e).__name__}: {e}"
        traceback.print_exc()
    finally:
        state["loading"] = False


def speak(text, lang, speed):
    key = hashlib.sha1(f"{state['voice']}|{lang}|{speed}|{text}".encode()).hexdigest()
    path = os.path.join(CACHE, key + ".wav")
    if os.path.exists(path):
        return open(path, "rb").read()
    with lock:
        audio = model.generate(text=text, language=lang_code(lang, text), voice_clone_prompt=prompt,
                               speed=speed, **gen_kwargs())[0]
    data = wav_bytes(audio, model.sampling_rate)
    with open(path, "wb") as f:
        f.write(data)
    trim_cache()
    return data


def trim_cache(limit=1500):
    files = sorted((os.path.join(CACHE, f) for f in os.listdir(CACHE)), key=os.path.getatime)
    for f in files[:-limit]:
        try:
            os.remove(f)
        except OSError:
            pass


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/health"):
            return self.send(200, state)
        if self.path.startswith("/sample") and os.path.exists(os.path.join(HOME, "voice-sample.wav")):
            return self.send(200, open(os.path.join(HOME, "voice-sample.wav"), "rb").read(), "audio/wav")
        self.send(404, {"error": "not found"})

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self.send(400, {"error": "bad json"})
        if not state["ready"]:
            return self.send(503, state)
        try:
            if self.path.startswith("/speak"):
                text = (req.get("text") or "").strip()[:600]
                if not text:
                    return self.send(400, {"error": "no text"})
                return self.send(200, speak(text, req.get("lang") or "en", float(req.get("speed") or 1.0)), "audio/wav")
            if self.path.startswith("/voice"):
                with lock:
                    if req.get("ref_audio"):
                        make_voice_from_recording(req["ref_audio"], req.get("ref_text"))
                    else:
                        make_voice_from_design(req.get("instruct") or DEFAULT_INSTRUCT, req.get("lang") or "en")
                return self.send(200, state)
        except Exception as e:
            traceback.print_exc()
            return self.send(500, {"error": f"{type(e).__name__}: {e}"})
        self.send(404, {"error": "not found"})


if __name__ == "__main__":
    threading.Thread(target=load, daemon=True).start()
    log(f"Sparrow Studio voice listening on 127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
