### Local documentation and SDK layout

- **Extended API docs (offline copy)**
  - HTML snapshot: `docs/external/extended_api_site/index.html`
  - If a full mirror is needed, we can expand this snapshot on request.
  - Source reference: `https://api.docs.extended.exchange`

- **Extended Python SDK (vendored source)**
  - Path: `vendor/python_sdk/`
  - Upstream repository: `https://github.com/x10xchange/python_sdk`
  - Useful local entry points:
    - `vendor/python_sdk/README.md`
    - `vendor/python_sdk/examples/`
    - `vendor/python_sdk/x10/` (SDK package code)

- **Quick references (this repo)**
  - API summary: `docs/external/extended_api_summary.md`
  - SDK usage notes: `docs/external/python_sdk_README.md`

Notes:
- We attempted to fetch an OpenAPI spec at `https://api.docs.extended.exchange/openapi.json`, but it was not available (404). If you have a spec URL, add it under `docs/external/extended_openapi.json`.
- All materials above are stored locally for offline use during development.


