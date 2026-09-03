# Oxygen web studio

The Oxygen studio configures, launches, filters, and investigates PerfChecker
runs in a browser. WGLMakie and the built-in interactive SVG renderer provide
drill-down views without changing what runs inside a measurement worker.

```julia
using PerfChecker, Oxygen, WGLMakie

serve_suite(
    "perf/results";
    host = "127.0.0.1",
    port = 8080,
)
```

Open `http://127.0.0.1:8080/perfchecker/v1/`.

## Studio workflow

The studio uses the shared suite-plan and UI-configuration contracts to:

- select packages, features, check types, releases, and Git targets;
- choose ranges instead of dragging every version card;
- filter and sort long result histories;
- attach colour labels and reorder selections;
- launch a local or authorized remote job and follow progress;
- open matching artifacts, logs, allocation views, distributions, and flame
  graphs;
- serialize query/filter state so a documentation page or agent can open the
  same evidence.

<figure class="doc-screenshot">
  <img src="/assets/screenshots/web-studio.png" alt="PerfChecker Oxygen web studio showing a software suite and performance results" loading="lazy">
  <figcaption>The same suite plan drives selection, execution, progress, and interactive result inspection.</figcaption>
</figure>

## Safety boundary

Loopback is the default. Binding to a non-loopback address is rejected unless
`allow_remote_control=true` and an authenticator is installed. This protects
against accidentally exposing an endpoint that can execute package workloads.

```julia
auth = studio_token_authenticator("perf/users.toml")

serve_suite("perf/results";
    host = "0.0.0.0",
    port = 8080,
    allow_remote_control = true,
    authenticator = auth,
)
```

The built-in token store keeps SHA-256 token digests and supports `admin`,
`runner`, and `agent` roles with optional allowed-agent IDs. Browser sessions use
HttpOnly cookies and state-changing requests are protected by CSRF checks. TLS,
token issuance/rotation, reverse-proxy hardening, backups, and public deployment
remain operator responsibilities.

See [hosted controller and agents](../operations/hosted.md) before exposing a
controller outside a developer workstation.
