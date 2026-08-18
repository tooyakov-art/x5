const MINIMAX_ENDPOINT = "https://api.minimax.io/v1/t2a_v2";
export const MINIMAX_MODEL = "speech-2.8-turbo";
const ELEVENLABS_ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech";
export const ELEVENLABS_MODEL = "eleven_v3";
const MAXIMUM_AUDIO_BYTES = 20 * 1024 * 1024;

const FEMALE_VOICES = new Set([
  "Aria",
  "Sarah",
  "Laura",
  "River",
  "Charlotte",
  "Alice",
  "Matilda",
  "Jessica",
  "Lily",
  "Rachel",
]);
const MINIMAX_FEMALE = [
  "Russian_BrightHeroine",
  "Russian_AmbitiousWoman",
  "Russian_CrazyQueen",
  "Russian_PessimisticGirl",
];
const MINIMAX_MALE = [
  "Russian_ReliableMan",
  "Russian_AttractiveGuy",
  "Russian_Bad-temperedBoy",
  "Russian_HandsomeChildhoodFriend",
];
const ELEVENLABS_VOICE_IDS = {
  Aria: "9BWtsMINqrJLrRacOk9x",
  Roger: "CwhRBWXzGAHq8TQ4Fs17",
  Sarah: "EXAVITQu4vr4xnSDxMaL",
  Laura: "FGY2WhTYpPnrIDTdsKH5",
  Charlie: "IKne3meq5aSn9XLyUdCD",
  George: "JBFqnCBsd6RMkjVDRZzb",
  Callum: "N2lVS1w4EtoT3dr4eOWO",
  River: "SAz9YHcvj6GT2YYXdXww",
  Liam: "TX3LPaxmHKxFdv7VOQHJ",
  Charlotte: "XB0fDUnXU5powFXDhCwa",
  Alice: "Xb7hH8MSUJpSbSDYk0k2",
  Matilda: "XrExE9yKIg1WjnnlVkGX",
  Will: "bIHbv24MWmeRgasZH58o",
  Jessica: "cgSgspJ2msm6clMCkdW9",
  Eric: "cjVigY5qzO86Huf0OWal",
  Chris: "iP95p4xoKVk53GoZ742B",
  Brian: "nPczCjzI2devNBz1zQrb",
  Daniel: "onwK4e9ZLuTAKqWW03F9",
  Lily: "pFZP5JQG7iQjIQuC4Bku",
  Bill: "pqHfZKP75CvOlQylNhV4",
  Rachel: "21m00Tcm4TlvDq8ikWAM",
};

export class DirectVoiceProviderError extends Error {
  constructor(code, options = {}) {
    super(code);
    this.name = "DirectVoiceProviderError";
    this.code = code;
    this.submissionAmbiguous = options.submissionAmbiguous === true;
    this.terminal = options.terminal !== false;
    this.providerStatus = Number.isInteger(options.providerStatus)
      ? options.providerStatus
      : null;
  }
}

export class DirectVoiceProvider {
  constructor({ minimaxKey = "", elevenLabsKey = "", fetchImpl = fetch }) {
    this.minimaxKey = String(minimaxKey || "").trim();
    this.elevenLabsKey = String(elevenLabsKey || "").trim();
    this.fetchImpl = fetchImpl;
    if (!this.minimaxKey && !this.elevenLabsKey) {
      throw new DirectVoiceProviderError("provider_not_configured");
    }
  }

  async generate({ input }) {
    if (this.minimaxKey) {
      try {
        return await this.#generateMiniMax(input);
      } catch (error) {
        if (error?.submissionAmbiguous === true || !this.elevenLabsKey) {
          throw error;
        }
      }
    }
    return await this.#generateElevenLabs(input);
  }

  async #generateMiniMax(input) {
    let response;
    try {
      response = await this.fetchImpl(MINIMAX_ENDPOINT, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.minimaxKey}`,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify({
          model: MINIMAX_MODEL,
          text: input.text,
          stream: false,
          language_boost: languageBoost(input.languageCode),
          output_format: "hex",
          voice_setting: {
            voice_id: minimaxVoice(input.voice),
            speed: input.speed,
            vol: 1,
            pitch: 0,
          },
          audio_setting: {
            sample_rate: 44_100,
            bitrate: 128_000,
            format: "mp3",
            channel: 1,
          },
        }),
        signal: AbortSignal.timeout(90_000),
      });
    } catch {
      throw new DirectVoiceProviderError("minimax_transport_ambiguous", {
        submissionAmbiguous: true,
        terminal: false,
      });
    }
    const payload = await response.json().catch(() => null);
    const providerCode = Number(payload?.base_resp?.status_code ?? -1);
    if (!response.ok || providerCode !== 0) {
      throw new DirectVoiceProviderError("minimax_rejected", {
        providerStatus: response.status,
      });
    }
    const audioBytes = decodeBoundedHex(payload?.data?.audio);
    const traceID = normalizeRequestID(payload?.trace_id, "minimax");
    return {
      provider: "minimax",
      model: MINIMAX_MODEL,
      requestID: traceID,
      audioBytes,
      audioMimeType: "audio/mpeg",
    };
  }

  async #generateElevenLabs(input) {
    const voiceID = ELEVENLABS_VOICE_IDS[input.voice];
    if (!this.elevenLabsKey || !voiceID) {
      throw new DirectVoiceProviderError("elevenlabs_not_configured");
    }
    let response;
    try {
      response = await this.fetchImpl(
        `${ELEVENLABS_ENDPOINT}/${
          encodeURIComponent(voiceID)
        }?output_format=mp3_44100_128`,
        {
          method: "POST",
          headers: {
            "xi-api-key": this.elevenLabsKey,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
          },
          body: JSON.stringify({
            text: input.text,
            model_id: ELEVENLABS_MODEL,
            ...(input.languageCode
              ? { language_code: input.languageCode }
              : {}),
            voice_settings: {
              stability: input.stability,
              similarity_boost: 0.75,
              speed: input.speed,
            },
          }),
          signal: AbortSignal.timeout(90_000),
        },
      );
    } catch {
      throw new DirectVoiceProviderError("elevenlabs_transport_ambiguous", {
        submissionAmbiguous: true,
        terminal: false,
      });
    }
    if (!response.ok) {
      throw new DirectVoiceProviderError("elevenlabs_rejected", {
        providerStatus: response.status,
      });
    }
    const declaredLength = Number(response.headers.get("Content-Length") || 0);
    if (declaredLength > MAXIMUM_AUDIO_BYTES) {
      throw new DirectVoiceProviderError("elevenlabs_audio_too_large");
    }
    const audioBytes = new Uint8Array(await response.arrayBuffer());
    if (
      audioBytes.byteLength <= 3 || audioBytes.byteLength > MAXIMUM_AUDIO_BYTES
    ) {
      throw new DirectVoiceProviderError("elevenlabs_audio_invalid");
    }
    const headerID = response.headers.get("request-id") || crypto.randomUUID();
    return {
      provider: "elevenlabs",
      model: ELEVENLABS_MODEL,
      requestID: normalizeRequestID(headerID, "eleven"),
      audioBytes,
      audioMimeType: "audio/mpeg",
    };
  }
}

function minimaxVoice(voice) {
  const source = FEMALE_VOICES.has(voice) ? MINIMAX_FEMALE : MINIMAX_MALE;
  let hash = 0;
  for (const character of String(voice || "")) {
    hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  }
  return source[hash % source.length];
}

function languageBoost(code) {
  const map = {
    ru: "Russian",
    en: "English",
    uk: "Ukrainian",
    de: "German",
    fr: "French",
    es: "Spanish",
    it: "Italian",
    pt: "Portuguese",
    tr: "Turkish",
    pl: "Polish",
    ja: "Japanese",
    ko: "Korean",
  };
  return map[String(code || "").toLowerCase()] || "auto";
}

function decodeBoundedHex(value) {
  const hex = String(value || "");
  if (!/^[0-9a-f]+$/i.test(hex) || hex.length % 2 !== 0) {
    throw new DirectVoiceProviderError("minimax_audio_invalid");
  }
  const byteLength = hex.length / 2;
  if (byteLength <= 3 || byteLength > MAXIMUM_AUDIO_BYTES) {
    throw new DirectVoiceProviderError("minimax_audio_too_large");
  }
  const bytes = new Uint8Array(byteLength);
  for (let index = 0; index < byteLength; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function normalizeRequestID(value, prefix) {
  const clean = String(value || "").replace(/[^A-Za-z0-9_-]/g, "_");
  const candidate = `${prefix}_${clean}`.slice(0, 200);
  if (candidate.length < 8) {
    return `${prefix}_${crypto.randomUUID()}`;
  }
  return candidate;
}
