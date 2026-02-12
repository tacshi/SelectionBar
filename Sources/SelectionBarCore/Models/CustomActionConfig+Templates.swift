import Foundation

extension CustomActionConfig {
  public static func createAllBuiltInTemplates() -> [CustomActionConfig] {
    [
      createPolishTemplate(),
      createCleanUpTemplate(),
      createActionItemsTemplate(),
      createSummaryTemplate(),
      createBulletPointsTemplate(),
      createEmailDraftTemplate(),
    ]
  }

  private static var polishPrompt: String {
    """
    Polish the following selected text into clean, readable text.

    Rules:
    - Add proper punctuation, capitalization, and paragraph breaks
    - Fix obvious typos or grammar mistakes only when confident
    - Keep original wording, tone, and meaning; do not rewrite
    - Preserve technical terms, names, numbers, and URLs
    - Keep the original language
    - Output only the polished text

    Selected text:
    {{TEXT}}
    """
  }

  public static func createPolishTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Polish",
      prompt: polishPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "polish"
    )
  }

  private static var cleanUpPrompt: String {
    """
    Clean up this selected text with minimal edits.

    Rules:
    - Remove obvious noise such as repeated words, accidental duplicates, and spacing issues
    - Keep only the final intended wording if there is an obvious self-correction
    - Do not rephrase or change meaning
    - Keep original language
    - Output only the cleaned text

    Selected text:
    {{TEXT}}
    """
  }

  public static func createCleanUpTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Clean Up",
      prompt: cleanUpPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "cleanup"
    )
  }

  private static var actionItemsPrompt: String {
    """
    Extract all action items from this selected text.

    Rules:
    - Return a bullet list using "- "
    - Include owners and deadlines when they are explicitly mentioned
    - Preserve order of appearance in the selected text
    - If none, output "No action items found."
    - Output only the list

    Selected text:
    {{TEXT}}
    """
  }

  public static func createActionItemsTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Extract Actions",
      prompt: actionItemsPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "action-items"
    )
  }

  private static var summaryPrompt: String {
    """
    Summarize this selected text concisely.

    Rules:
    - Use 2-4 sentences
    - Capture key points and outcomes
    - Keep original language
    - Output only the summary

    Selected text:
    {{TEXT}}
    """
  }

  public static func createSummaryTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Summarize",
      prompt: summaryPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "summary"
    )
  }

  private static var bulletPointsPrompt: String {
    """
    Convert this selected text into a concise bullet list.

    Rules:
    - Use "- " bullets
    - One key point per bullet
    - Keep original language
    - Output only the bullet list

    Selected text:
    {{TEXT}}
    """
  }

  public static func createBulletPointsTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Bulletize",
      prompt: bulletPointsPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "bullet-points"
    )
  }

  private static var emailDraftPrompt: String {
    """
    Turn this selected text into a well-formatted email.

    Rules:
    - Add greeting and sign-off
    - Organize into clear paragraphs
    - Preserve key details and intent
    - Keep original language
    - Output only the email body

    Selected text:
    {{TEXT}}
    """
  }

  public static func createEmailDraftTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Draft Email",
      prompt: emailDraftPrompt,
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      isEnabled: false,
      isBuiltIn: true,
      templateId: "email-draft"
    )
  }

  public static func createJavaScriptStarterTemplates() -> [CustomActionConfig] {
    [
      createJavaScriptTrimNormalizeTemplate(),
      createJavaScriptTitleCaseTemplate(),
      createJavaScriptURLToolkitTemplate(),
      createJavaScriptJWTDecodeTemplate(),
      createJavaScriptFormatJSONTemplate(),
      createJavaScriptTimestampConverterTemplate(),
      createJavaScriptCleanEscapesTemplate(),
      createJavaScriptWrapQuoteTemplate(),
    ]
  }

  public static func createJavaScriptTrimNormalizeTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Trim + Normalize Whitespace",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: """
        function transform(input) {
          return input
            .trim()
            .replace(/[ \\t]+/g, " ")
            .replace(/\\n{3,}/g, "\\n\\n");
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-trim-normalize",
      icon: CustomActionIcon(value: "text.badge.checkmark")
    )
  }

  public static func createJavaScriptTitleCaseTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Title Case",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: """
        function transform(input) {
          return input.toLowerCase().replace(/\\b\\w/g, c => c.toUpperCase());
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-title-case",
      icon: CustomActionIcon(value: "textformat")
    )
  }

  public static func createJavaScriptURLToolkitTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "URL Toolkit",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: """
        function transform(input) {
          const trimmed = input.trim();
          if (!trimmed) {
            return input;
          }

          const safeDecode = (value) => {
            if (value.length === 0) {
              return "";
            }
            try {
              return decodeURIComponent(value.replace(/\\+/g, "%20"));
            } catch (error) {
              return value;
            }
          };

          const safeEncode = (value) => {
            try {
              return encodeURIComponent(value).replace(/%20/g, "+");
            } catch (error) {
              return value;
            }
          };

          const parseOne = (rawInput) => {
            const text = rawInput.trim();
            if (!text) {
              return null;
            }

            const looksLikeQuery =
              !text.includes("://")
              && (text.startsWith("?")
                || /^[^\\s?#=&]+=[^\\s#]*(?:&[^\\s?#=&]+=[^\\s#]*)*$/.test(text));
            const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text);

            let normalized = text;
            if (looksLikeQuery) {
              normalized = `https://example.local/?${text.replace(/^\\?/, "")}`;
            } else if (!hasScheme && /[./]/.test(text) && !text.startsWith("/")) {
              normalized = `https://${text}`;
            }

            let fragment = "";
            let withoutFragment = normalized;
            const hashIndex = withoutFragment.indexOf("#");
            if (hashIndex >= 0) {
              fragment = withoutFragment.slice(hashIndex + 1);
              withoutFragment = withoutFragment.slice(0, hashIndex);
            }

            let query = "";
            let withoutQuery = withoutFragment;
            const queryIndex = withoutQuery.indexOf("?");
            if (queryIndex >= 0) {
              query = withoutQuery.slice(queryIndex + 1);
              withoutQuery = withoutQuery.slice(0, queryIndex);
            }

            let scheme = "";
            let authority = "";
            let path = "";
            const schemeMatch = withoutQuery.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\\/\\/(.*)$/);
            if (schemeMatch) {
              scheme = schemeMatch[1].toLowerCase();
              const remainder = schemeMatch[2];
              const slashIndex = remainder.indexOf("/");
              if (slashIndex >= 0) {
                authority = remainder.slice(0, slashIndex);
                path = remainder.slice(slashIndex);
              } else {
                authority = remainder;
                path = "/";
              }
            } else {
              path = withoutQuery || "/";
            }

            let username = "";
            let password = "";
            let hostPort = authority;
            const atIndex = authority.lastIndexOf("@");
            if (atIndex >= 0) {
              const credentials = authority.slice(0, atIndex);
              hostPort = authority.slice(atIndex + 1);
              const separator = credentials.indexOf(":");
              if (separator >= 0) {
                username = safeDecode(credentials.slice(0, separator));
                password = safeDecode(credentials.slice(separator + 1));
              } else {
                username = safeDecode(credentials);
              }
            }

            let host = hostPort;
            let port = "";
            if (hostPort.startsWith("[")) {
              const endBracket = hostPort.indexOf("]");
              if (endBracket >= 0) {
                host = hostPort.slice(0, endBracket + 1);
                if (hostPort[endBracket + 1] === ":") {
                  port = hostPort.slice(endBracket + 2);
                }
              }
            } else {
              const colonIndex = hostPort.lastIndexOf(":");
              if (colonIndex > 0 && hostPort.indexOf(":") === colonIndex) {
                host = hostPort.slice(0, colonIndex);
                port = hostPort.slice(colonIndex + 1);
              }
            }

            const params = [];
            if (query) {
              for (const segment of query.split("&")) {
                if (!segment) {
                  continue;
                }
                const equalsIndex = segment.indexOf("=");
                const rawKey = equalsIndex >= 0 ? segment.slice(0, equalsIndex) : segment;
                const rawValue = equalsIndex >= 0 ? segment.slice(equalsIndex + 1) : "";
                params.push({
                  rawKey,
                  rawValue,
                  key: safeDecode(rawKey),
                  value: safeDecode(rawValue),
                });
              }
            }

            const normalizedQuery = params
              .map(({ key, value }) => `${safeEncode(key)}=${safeEncode(value)}`)
              .join("&");
            const normalizedPath = path || "/";
            const normalizedOutput =
              scheme
              ? `${scheme}://${authority}${normalizedPath}${normalizedQuery ? `?${normalizedQuery}` : ""}${fragment ? `#${fragment}` : ""}`
              : `${normalizedPath}${normalizedQuery ? `?${normalizedQuery}` : ""}${fragment ? `#${fragment}` : ""}`;

            return {
              input: text,
              normalizedOutput,
              scheme,
              username,
              password,
              host,
              port,
              path: safeDecode(normalizedPath),
              fragment: safeDecode(fragment),
              params,
              looksLikeQuery,
            };
          };

          const formatOne = (parsed) => {
            if (!parsed) {
              return null;
            }

            const lines = [];
            lines.push(`Input: ${parsed.input}`);
            lines.push(`Normalized: ${parsed.normalizedOutput}`);
            if (parsed.looksLikeQuery) {
              lines.push("Detected as: Query string");
            }
            lines.push(`Scheme: ${parsed.scheme || "(none)"}`);
            lines.push(`Host: ${parsed.host || "(none)"}`);
            lines.push(`Port: ${parsed.port || "(none)"}`);
            lines.push(`Path: ${parsed.path || "/"}`);
            lines.push(`Fragment: ${parsed.fragment || "(none)"}`);
            if (parsed.username) {
              lines.push(`Username: ${parsed.username}`);
            }
            if (parsed.password) {
              lines.push(`Password: ${"*".repeat(Math.min(parsed.password.length, 8))}`);
            }

            if (parsed.params.length === 0) {
              lines.push("Query Params: (none)");
            } else {
              lines.push("Query Params:");
              parsed.params.forEach((param, index) => {
                lines.push(`${index + 1}. ${param.key} = ${param.value}`);
              });
            }

            return lines.join("\\n");
          };

          const lines = trimmed
            .split(/\\r?\\n/)
            .map(line => line.trim())
            .filter(Boolean);
          const inputs = lines.length > 1 ? lines : [trimmed];
          const outputs = inputs
            .map(value => formatOne(parseOne(value)))
            .filter(Boolean);

          if (outputs.length === 0) {
            return "No URL or query string detected.";
          }

          return outputs.join("\\n\\n---\\n\\n");
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-url-toolkit",
      icon: CustomActionIcon(value: "link")
    )
  }

  public static func createJavaScriptJWTDecodeTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "JWT Decode",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: """
        function transform(input) {
          const trimmed = input.trim();
          if (!trimmed) {
            return input;
          }

          const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

          const bytesToUTF8 = (bytes) => {
            let output = "";
            for (let index = 0; index < bytes.length; ) {
              const first = bytes[index++];
              if (first < 0x80) {
                output += String.fromCharCode(first);
                continue;
              }

              if ((first & 0xE0) === 0xC0 && index < bytes.length) {
                const second = bytes[index++];
                output += String.fromCharCode(((first & 0x1F) << 6) | (second & 0x3F));
                continue;
              }

              if ((first & 0xF0) === 0xE0 && index + 1 < bytes.length) {
                const second = bytes[index++];
                const third = bytes[index++];
                output += String.fromCharCode(
                  ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F)
                );
                continue;
              }

              if ((first & 0xF8) === 0xF0 && index + 2 < bytes.length) {
                const second = bytes[index++];
                const third = bytes[index++];
                const fourth = bytes[index++];
                const codePoint =
                  ((first & 0x07) << 18)
                  | ((second & 0x3F) << 12)
                  | ((third & 0x3F) << 6)
                  | (fourth & 0x3F);
                output += String.fromCodePoint(codePoint);
                continue;
              }

              output += "\\uFFFD";
            }
            return output;
          };

          const base64UrlToBytes = (segment) => {
            const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
            const padding = (4 - (normalized.length % 4)) % 4;
            const padded = normalized + "=".repeat(padding);

            let bits = 0;
            let value = 0;
            const bytes = [];
            for (const character of padded) {
              if (character === "=") {
                break;
              }
              const mapped = alphabet.indexOf(character);
              if (mapped < 0) {
                throw new Error("Invalid Base64URL token");
              }

              value = (value << 6) | mapped;
              bits += 6;
              if (bits >= 8) {
                bits -= 8;
                bytes.push((value >> bits) & 0xFF);
                value &= (1 << bits) - 1;
              }
            }
            return bytes;
          };

          const decodeSegment = (label, segment) => {
            try {
              const bytes = base64UrlToBytes(segment);
              const text = bytesToUTF8(bytes);
              let json = null;
              try {
                json = JSON.parse(text);
              } catch (error) {
                json = null;
              }
              return { label, text, json, error: null };
            } catch (error) {
              return {
                label,
                text: "",
                json: null,
                error: error instanceof Error ? error.message : String(error),
              };
            }
          };

          const formatNumericDate = (value) => {
            if (typeof value !== "number" || !Number.isFinite(value)) {
              return null;
            }
            const milliseconds = Math.abs(value) >= 1e12 ? value : value * 1000;
            const date = new Date(milliseconds);
            if (Number.isNaN(date.getTime())) {
              return null;
            }
            return date.toISOString();
          };

          const token = trimmed.replace(/^Bearer\\s+/i, "").split(/\\s+/)[0];
          const segments = token.split(".");
          if (segments.length < 2) {
            return [
              "Invalid JWT format.",
              "Expected: header.payload.signature",
            ].join("\\n");
          }

          const header = decodeSegment("Header", segments[0]);
          const payload = decodeSegment("Payload", segments[1]);
          const signature = segments.length >= 3 ? segments[2] : "";

          const lines = [];
          lines.push(`Token: ${token}`);
          lines.push(`Signature present: ${signature.length > 0 ? "yes" : "no"}`);
          lines.push("");

          const appendSection = (section) => {
            lines.push(`${section.label}:`);
            if (section.error) {
              lines.push(`  Decode error: ${section.error}`);
              return;
            }
            if (section.json && typeof section.json === "object") {
              const formatted = JSON.stringify(section.json, null, 2) ?? section.text;
              for (const line of formatted.split("\\n")) {
                lines.push(`  ${line}`);
              }
            } else {
              lines.push(`  ${section.text}`);
            }
          };

          appendSection(header);
          lines.push("");
          appendSection(payload);

          if (payload.json && typeof payload.json === "object") {
            const payloadObject = payload.json;
            const dateFields = ["iat", "nbf", "exp"];
            const annotations = [];
            for (const field of dateFields) {
              const iso = formatNumericDate(payloadObject[field]);
              if (iso) {
                annotations.push(`${field}: ${payloadObject[field]} (${iso})`);
              }
            }
            if (annotations.length > 0) {
              lines.push("");
              lines.push("Numeric date fields:");
              for (const note of annotations) {
                lines.push(`- ${note}`);
              }
            }
          }

          lines.push("");
          lines.push("Note: Decoding does not verify signature authenticity.");

          return lines.join("\\n");
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-jwt-decode",
      icon: CustomActionIcon(value: "key.horizontal")
    )
  }

  public static func createJavaScriptWrapQuoteTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Wrap as Quote",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: """
        function transform(input) {
          const lines = input.split(/\\r?\\n/);
          return lines.map(line => line.length === 0 ? ">" : `> ${line}`).join("\\n");
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-wrap-quote",
      icon: CustomActionIcon(value: "quote.bubble")
    )
  }

  public static func createJavaScriptFormatJSONTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Format JSON",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: """
        function transform(input) {
          const trimmed = input.trim();
          if (!trimmed) {
            return input;
          }

          try {
            const value = JSON.parse(trimmed);
            return JSON.stringify(value, null, 2);
          } catch (error) {
            return input;
          }
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-format-json",
      icon: CustomActionIcon(value: "curlybraces")
    )
  }

  public static func createJavaScriptTimestampConverterTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Convert Timestamps",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .resultWindow,
      script: """
        function transform(input) {
          const trimmed = input.trim();
          if (!trimmed) {
            return input;
          }

          const candidates = [];
          const seen = new Set();
          const NS_PER_SECOND = 1000000000n;
          const NS_PER_MILLISECOND = 1000000n;
          const NS_PER_MICROSECOND = 1000n;

          const addCandidate = (raw, date, detectedAs, epochNs) => {
            if (!Number.isFinite(date.getTime())) {
              return;
            }

            const key = `${raw}::${epochNs.toString()}::${detectedAs}`;
            if (seen.has(key)) {
              return;
            }

            seen.add(key);
            candidates.push({ raw, date, detectedAs, epochNs });
          };

          const parseEpoch = (text) => {
            const value = text.trim();
            if (!/^-?\\d+$/.test(value)) {
              return null;
            }

            let epochInteger;
            try {
              epochInteger = BigInt(value);
            } catch (error) {
              return null;
            }

            const digits = value.replace(/^-/, "").length;
            let epochNs = 0n;
            let unit = "milliseconds";
            if (digits <= 10) {
              epochNs = epochInteger * NS_PER_SECOND;
              unit = "seconds";
            } else if (digits <= 13) {
              epochNs = epochInteger * NS_PER_MILLISECOND;
              unit = "milliseconds";
            } else if (digits <= 16) {
              epochNs = epochInteger * NS_PER_MICROSECOND;
              unit = "microseconds";
            } else {
              epochNs = epochInteger;
              unit = "nanoseconds";
            }

            const epochMs = Number(epochNs / NS_PER_MILLISECOND);
            if (!Number.isFinite(epochMs)) {
              return null;
            }

            const date = new Date(epochMs);
            if (Number.isNaN(date.getTime())) {
              return null;
            }

            return { date, unit, epochNs };
          };

          const parseDateText = (text) => {
            const ms = Date.parse(text);
            if (!Number.isFinite(ms)) {
              return null;
            }
            const date = new Date(ms);
            if (Number.isNaN(date.getTime())) {
              return null;
            }
            const epochNs = BigInt(Math.trunc(ms)) * NS_PER_MILLISECOND;
            return { date, epochNs };
          };

          const maybeAddToken = (token) => {
            const normalized = token
              .trim()
              .replace(/^[\\[\\(\\"']+|[\\]\\)\\.,;:\\"']+$/g, "");
            if (!normalized) {
              return;
            }

            const epochParsed = parseEpoch(normalized);
            if (epochParsed) {
              addCandidate(
                normalized,
                epochParsed.date,
                `Unix timestamp (${epochParsed.unit})`,
                epochParsed.epochNs
              );
              return;
            }

            const dateParsed = parseDateText(normalized);
            if (dateParsed) {
              addCandidate(normalized, dateParsed.date, "Date/time string", dateParsed.epochNs);
            }
          };

          maybeAddToken(trimmed);

          for (const line of input.split(/\\r?\\n/)) {
            const value = line.trim();
            if (!value) {
              continue;
            }
            maybeAddToken(value);
          }

          const numberRegex = /-?\\d{10,30}/g;
          let numberMatch;
          while ((numberMatch = numberRegex.exec(input)) !== null) {
            const token = numberMatch[0];
            const start = numberMatch.index;
            const end = start + token.length;
            const prev = start > 0 ? input[start - 1] : "";
            const next = end < input.length ? input[end] : "";
            if (/\\d/.test(prev) || /\\d/.test(next)) {
              continue;
            }
            maybeAddToken(token);
          }

          const isoRegex =
            /\\d{4}-\\d{2}-\\d{2}(?:[ T]\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d{1,9})?)?)?(?:Z|[+-]\\d{2}:?\\d{2})?/g;
          let isoMatch;
          while ((isoMatch = isoRegex.exec(input)) !== null) {
            maybeAddToken(isoMatch[0]);
          }

          if (candidates.length === 0) {
            return [
              "No supported timestamp found.",
              "",
              "Supported formats:",
              "- Unix timestamp: seconds, milliseconds, microseconds, nanoseconds",
              "- ISO 8601 / RFC 2822 / common date-time strings",
              "",
              "Examples:",
              "- 1704067200",
              "- 1704067200000",
              "- 2024-01-01T00:00:00Z",
            ].join("\\n");
          }

          const formatScaled = (valueNs, scaleNs, fractionDigits) => {
            const isNegative = valueNs < 0n;
            const absoluteNs = isNegative ? -valueNs : valueNs;
            const integerPart = absoluteNs / scaleNs;
            const remainder = absoluteNs % scaleNs;
            const sign = isNegative ? "-" : "";
            if (remainder === 0n) {
              return `${sign}${integerPart.toString()}`;
            }

            const fraction = remainder
              .toString()
              .padStart(fractionDigits, "0")
              .replace(/0+$/, "");
            return `${sign}${integerPart.toString()}.${fraction}`;
          };

          const pad = (value, width = 2) => String(Math.abs(Math.trunc(value))).padStart(width, "0");

          const localISOString = (date) => {
            const year = date.getFullYear();
            const month = pad(date.getMonth() + 1);
            const day = pad(date.getDate());
            const hour = pad(date.getHours());
            const minute = pad(date.getMinutes());
            const second = pad(date.getSeconds());
            const millisecond = pad(date.getMilliseconds(), 3);

            const offsetMinutes = -date.getTimezoneOffset();
            const offsetSign = offsetMinutes >= 0 ? "+" : "-";
            const offsetAbs = Math.abs(offsetMinutes);
            const offsetHour = pad(Math.floor(offsetAbs / 60));
            const offsetMinute = pad(offsetAbs % 60);

            return `${year}-${month}-${day}T${hour}:${minute}:${second}.${millisecond}${offsetSign}${offsetHour}:${offsetMinute}`;
          };

          const sections = candidates.map((candidate) => {
            const epochSeconds = formatScaled(candidate.epochNs, NS_PER_SECOND, 9);
            const epochMilliseconds = formatScaled(candidate.epochNs, NS_PER_MILLISECOND, 6);
            const epochMicroseconds = formatScaled(candidate.epochNs, NS_PER_MICROSECOND, 3);
            const epochNanoseconds = candidate.epochNs.toString();

            return [
              `Input: ${candidate.raw}`,
              `Detected as: ${candidate.detectedAs}`,
              `UTC ISO 8601: ${candidate.date.toISOString()}`,
              `Local ISO 8601: ${localISOString(candidate.date)}`,
              `Epoch seconds: ${epochSeconds}`,
              `Epoch milliseconds: ${epochMilliseconds}`,
              `Epoch microseconds: ${epochMicroseconds}`,
              `Epoch nanoseconds: ${epochNanoseconds}`,
              `RFC 2822 (UTC): ${candidate.date.toUTCString()}`,
            ].join("\\n");
          });

          return sections.join("\\n\\n---\\n\\n");
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-convert-timestamps",
      icon: CustomActionIcon(value: "clock.arrow.circlepath")
    )
  }

  public static func createJavaScriptCleanEscapesTemplate() -> CustomActionConfig {
    CustomActionConfig(
      name: "Clean Up Escapes",
      prompt: Self.defaultPromptTemplate,
      modelProvider: "",
      modelId: "",
      kind: .javascript,
      outputMode: .inplace,
      script: """
        function transform(input) {
          if (!input) {
            return input;
          }

          let output = input;

          const decodePass = (text) => text
            .replace(/\\\\+u\\{([0-9a-fA-F]+)\\}/g, (_, hex) =>
              String.fromCodePoint(parseInt(hex, 16)))
            .replace(/\\\\+u([0-9a-fA-F]{4})/g, (_, hex) =>
              String.fromCharCode(parseInt(hex, 16)))
            .replace(/\\\\+x([0-9a-fA-F]{2})/g, (_, hex) =>
              String.fromCharCode(parseInt(hex, 16)))
            .replace(/\\\\+n/g, "\\n")
            .replace(/\\\\+r/g, "\\r")
            .replace(/\\\\+t/g, "\\t")
            .replace(/\\\\+f/g, "\\f")
            .replace(/\\\\+b/g, "\\b")
            .replace(/\\\\+\\//g, "/")
            .replace(/\\\\+"/g, "\\"")
            .replace(/\\\\+'/g, "'")
            .replace(/\\\\{2,}/g, "\\\\");

          // Run a few passes so doubly-escaped text gets fully normalized.
          for (let i = 0; i < 3; i += 1) {
            const next = decodePass(output);
            if (next === output) {
              break;
            }
            output = next;
          }

          return output;
        }
        """,
      isEnabled: false,
      isBuiltIn: true,
      templateId: "js-clean-escapes",
      icon: CustomActionIcon(value: "eraser.xmark")
    )
  }
}
