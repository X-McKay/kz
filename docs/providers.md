# Model providers

The initial development profile uses the OpenAI-compatible endpoint at `https://llm.almckay.io/v1` and the currently advertised `Qwen3.6-35B-A3B-NVFP4` model.

## Architecture

Provider identity and protocol are separate:

```text
diagnosis engine
      |
      v
Provider interface
      |
      +-- OpenAI-compatible adapter --> llm.almckay.io
      +-- future adapter ------------> another protocol
      +-- fixture adapter -----------> deterministic CI
```

`src/model_provider.zig` owns protocol-neutral messages, completion requests/responses, token usage, capability reporting, and the provider vtable. `src/providers/openai_compatible.zig` owns only OpenAI-compatible URL and authentication conventions. Policy, evidence validation, and remediation code do not import the adapter.

The Python evaluation runner uses the same separation through `provider` (profile name) and `provider_type` (adapter). Adding another provider type requires a new invocation adapter, not changes to scoring or cases.

## Initial profile

`config/kz.example.json` contains:

```json
{
  "active_provider": "almckay-llm",
  "providers": {
    "almckay-llm": {
      "protocol": "openai-compatible",
      "base_url": "https://llm.almckay.io/v1",
      "model": "Qwen3.6-35B-A3B-NVFP4",
      "api_key_env": "KZ_MODEL_API_KEY"
    }
  }
}
```

The endpoint currently accepts requests without an API key. If authentication is enabled later, set `KZ_MODEL_API_KEY`; `kz` must never persist or print its value. The adapter omits the Authorization header when the variable is absent—it does not send a fake placeholder token.

The endpoint was compatibility-probed for:

- `GET /v1/models`;
- `POST /v1/chat/completions`;
- `response_format: {"type":"json_object"}`;
- usage token accounting.

The advertised model emits reasoning tokens before final content. An initial 2,048-token run truncated one of six cases, so the profile uses a bounded 4,096-token ceiling. Responses with `finish_reason: "length"` are rejected rather than scored or acted upon.

## Switching endpoints or models

For mise-based development:

```bash
KZ_MODEL_BASE_URL=https://another.example/v1 \
KZ_MODEL=another-model \
KZ_MODEL_API_KEY=... \
python tests/evals/run.py \
  --provider openai-compatible \
  --models "$KZ_MODEL" \
  --max-output-tokens 4096 \
  --output .artifacts/evals/alternate.json
```

For multiple models or providers, copy `tests/evals/models.example.json` and add profiles. Incident cases and metrics remain identical, enabling direct accuracy, safety, token, and latency comparison.

Capability flags are explicit. An adapter must not assume tool calling, streaming, or strict JSON Schema merely because an endpoint is OpenAI-compatible. A strict-schema probe was accepted by the API but did not produce conclusive constrained output before exhausting its reasoning budget, so the almckay profile currently enables only the JSON-object behavior that was verified.

## Measured baseline

The latest 50-case baseline is generated into the repository README by `mise run model-benchmark`; the complete records remain in `.artifacts/evals/results.json`. Keeping the table generated avoids copying stale six-case results into provider documentation. Model output remains untrusted regardless of rank, and an out-of-vocabulary action always fails the objective.
