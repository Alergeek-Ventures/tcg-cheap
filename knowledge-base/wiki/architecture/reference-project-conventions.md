# Reference Project Conventions

- Updated: 2026-08-10
- Sources: Read-only source audits of `/home/kosciak/projects/alergeek/firmowid` at commit `8a18f66aa28ac8444b5b3445fa3c7b6613fdf056`, `/home/kosciak/projects/alergeek/onside` at commit `ac8d1d942a086bfe868043274fc0f430f30aacef`, and current TCG Cheap code
- Raw: N/A — codebase update

## Audit status and authority

Phase 0 reference inspection and convention recording is complete. Firmowid is the
primary implementation and UI-convention reference for a Phoenix/LiveView product
and mature Ash domain patterns. Onside is a secondary implementation reference
for backend-compatible Ash, Postgres, Oban, Req, scoped system actors, and
operations; it is not a public-UI reference because its product frontend is an
SPA. Neither repository defines TCG Cheap product requirements.

The audits were read-only. Firmowid was clean at the audited commit. Onside
already had an unrelated modified `shell.nix`; neither reference repository was
changed.

## Audit coverage and evidence

| Category | Evidence and finding |
| --- | --- |
| READMEs/instructions | Firmowid documents setup, feature-first frontend structure, Ash migrations, Conventional Commits, and `mix check` in `/home/kosciak/projects/alergeek/firmowid/README.md:25-50,52-83`; its repository instructions cover Phoenix/Ash/LiveView conventions and validation in `/home/kosciak/projects/alergeek/firmowid/AGENTS.md:73-116`. Onside documents `mix setup`, `mix dev.up/down`, worktrees, and `mix check` in `/home/kosciak/projects/alergeek/onside/README.md:3-70`; its instructions cover backend conventions, quality checks, operations, and explicitly identify the product frontend as an SPA in `/home/kosciak/projects/alergeek/onside/AGENTS.md:50-58,73-89,128-139`. |
| Dependencies/libraries | Firmowid declares Ash, AshPostgres, AshPhoenix, AshOban, AshAuthentication, Oban, Req, Tailwind, and esbuild in `/home/kosciak/projects/alergeek/firmowid/mix.exs:63-89,112-125`. Onside declares Ash, AshPostgres, AshPhoenix, AshOban, AshAuthentication, AshAdmin, Oban, Req, and Volt in `/home/kosciak/projects/alergeek/onside/mix.exs:65-105`. |
| Phoenix/LiveView | Both use the Phoenix LiveView compiler and LiveView 1.2 (`firmowid/mix.exs:13-16,84-86`; `onside/mix.exs:13-16,88-92`). TCG Cheap keeps the conventional Phoenix entrypoint and LiveView helpers in `/home/kosciak/projects/alergeek/tcg-cheap/lib/tcg_cheap_web.ex:49-91`. |
| Layouts/components/forms/validation | Adopt explicit TCG Cheap Phoenix components, layouts, unique form IDs, `to_form`, and LiveView validation conventions. Firmowid's `simple_form` `:let` style is observed in `/home/kosciak/projects/alergeek/firmowid/lib/firmowid_web/auth/views/login.ex:19-40` but is rejected in favor of the repository's current form rules. Reusable design-system components and resource validation patterns remain useful references (`firmowid/lib/firmowid_web/design_system/components/core_components.ex:243-273`; `firmowid/lib/firmowid/ash/timetracker/validations/project_access.ex:1-48`). |
| Ash domains/resources/actions | Firmowid separates domains and resource namespaces, with explicit actions and policies (`firmowid/lib/firmowid/ash/core/core.ex:12-24`; `firmowid/lib/firmowid/ash/core/organization.ex:30-158`). Onside similarly groups resource domains and adds generated interfaces (`onside/lib/onside/audits.ex:3-30`). Adopt domain/resource organization and specific actions; do not copy business models. |
| Ash auth/authz | Firmowid uses `Ash.Policy.Authorizer` and `AshAuthentication` on users (`firmowid/lib/firmowid/ash/core/user.ex:18-19,99-105,346-347`). Onside uses policy checks and scoped authorization, e.g. `onside/lib/onside/policy_checks/system_actor_scope.ex:1-40` and the admin bypass in `onside/lib/onside/audits.ex:268-272`. Adopt explicit policy boundaries and actor context. |
| Authentication | Firmowid has AshAuthentication, password/OAuth flows, token resources, and Phoenix routes (`firmowid/mix.exs:70-71`; `firmowid/lib/firmowid_web/core/router.ex:3-7`; `firmowid/lib/firmowid/ash/core/token.ex:10-29`). Onside has browser/mobile token paths (`onside/lib/onside_web/auth_controller.ex:3-81`; `onside/lib/onside_web/browser_socket.ex:5-12`). TCG Cheap now uses independently pinned AshAuthentication password/token support only for provisioned administrators, with no public registration, renewed/revoked sessions, dual IP/account throttling, and admin-only Ash policies around review actions. |
| Admin | Firmowid has no AshBackpex dependency or adopted AshBackpex convention. Onside uses AshAdmin, not AshBackpex (`onside/mix.exs:75-82`; `onside/lib/onside/audits.ex:3-6`). Neither admin UI was copied. TCG Cheap independently pins AshBackpex `0.1.12`/Backpex `0.19.6` and validates authenticated sealed-product, manual pending alias, and retailer curation plus retailer-listing, listing-product mapping/history, card-set/card external-mapping correction/history, and immutable single-valuation inspection. Focused review/operations, typed canonical manual refresh, and reasoned correction LiveViews remain the boundary for workflows generic CRUD cannot safely express. |
| Oban/jobs | Firmowid combines Oban and AshOban, including tenant-aware wrappers and AshOban startup configuration (`firmowid/lib/firmowid/application.ex:17-50`; `firmowid/lib/firmowid/oban.ex:1-12`). Onside configures AshOban and Oban in its application (`onside/lib/onside/application.ex:16-33`) and has queued, retrying workers such as `onside/lib/onside/clubs/workers/squadassist_sync_worker.ex:1-8,16-38`. Adopt explicit queues, worker tests, and observability only after product jobs are defined. |
| Provider boundaries | Onside wraps external SquadAssist calls behind a Req client (`onside/lib/onside/squadassist/client.ex:3-130`); Firmowid has a Req NBP client (`firmowid/lib/firmowid/ash/currencies/nbp_api_client.ex:27-75`). Adopt only the Req boundary and error-normalization pattern, not Firmowid's float rate representation: TCG Cheap money/rates require Decimal. The bounded experiment batch and cost/control analysis are recorded in the provider ADR; acquisition access is no longer vetoed under the scrappy policy, while exact seller-identity/destination capability validation remains unresolved, so production provider locking and Phase 0 remain incomplete. Older access-first wording is historical. |
| Styling/assets | Firmowid uses Phoenix-managed Tailwind/esbuild and self-contained JS hooks (`firmowid/mix.exs:87-88,208-219`; `firmowid/assets/js/hooks/index.js:1-20`). Onside's product UI is React/Volt SPA (`onside/mix.exs:65-67`; `onside/lib/onside_web/volt_react_dev_entry_plugin.ex:1-54`). Adopt neither SPA architecture nor Volt; TCG Cheap remains standard LiveView with Nix/devenv and its existing Tailwind/esbuild pipeline (`tcg-cheap/mix.exs:66-67,98-114`). |
| Tests/quality | Firmowid and Onside compile tests from `lib` and expose `mix check` (`firmowid/mix.exs:15-17`; `onside/mix.exs:15-17`). Firmowid has colocated tests and `test_paths: ["lib"]`; that colocated test convention is explicitly not adopted. TCG Cheap keeps standard `test/` structure and canonical `mix check`. |
| Development | Firmowid uses Compose, Infisical, `mix setup`, and `mix dev.up` (`firmowid/README.md:5-23,121-153`). Onside uses worktree-specific ports, Caddy, Infisical, and `mix dev.up/down` (`onside/README.md:36-70`). Adopt reproducible lifecycle and isolation ideas, but TCG Cheap remains Nix/devenv, direct localhost, and deferred Caddy integration. |
| Deployment/operations/docs | Firmowid documents S3-compatible storage and production environment variables (`firmowid/README.md:160-207`) and has container files under `firmowid/deployment/`. Onside has app and SeaweedFS container files and health/telemetry boundaries (`onside/deployment/Containerfile.app`; `onside/lib/onside_web/health_controller.ex:39-44`). TCG Cheap now adapts the verified pinned Debian release pattern, non-root runtime, release migration module, and JSON health boundary while separating liveness from readiness and adding its own deployment/operations runbook. A real production deployment, restore drill, and monitoring integration remain incomplete. |

## Decisions for TCG Cheap

### Directly adopted

- Keep feature/domain-first namespaces and explicit Ash domains/resources.
- Use Ash-generated migrations/codegen, AshPostgres, policy-driven authorization,
  specific actions, and code interfaces where they fit.
- Use Req for provider clients, with narrow provider boundaries and test seams.
- Preserve the standard Phoenix LiveView layouts/components/forms/test structure,
  Nix/devenv workflow, Tailwind/esbuild assets, and `mix check` quality gate.
- Treat actor/scope where authorization benefits, explicit provider/source/resource
  IDs, job arguments, and external provider calls as explicit data rather than
  hidden global state.

### Adapted or rejected

- Firmowid's `simple_form` `:let` form style is not adopted; use `to_form/2` and
  `Phoenix.Component.form/1` as required by TCG Cheap conventions.
- Firmowid's process-dictionary tenant workaround (`firmowid/lib/firmowid/repo.ex:29-61`)
  is not adopted. Any future authorization scope must be passed explicitly through
  Ash queries/actions and actor context; multitenancy is not introduced without a
  demonstrated requirement.
- Firmowid's colocated tests are not adopted; tests stay in the standard test tree.
- Onside's React/Volt SPA, AshAdmin UI, AshTypescript RPC, and mobile frontend are
  not copied. The product surface is LiveView-first.
- AshBackpex, AshAuthentication, and Oban were added only after concrete MVP boundaries
  and compatibility were validated; AshOban and storage libraries are not added merely
  because references use them. The same standard still applies to remaining tools.

## Version compatibility

At lock level, TCG Cheap and Onside currently share Phoenix `1.8.9`, Ash `3.31.0`,
and AshPostgres `2.11.0` (`tcg-cheap/mix.lock:2,5,41`; `onside/mix.lock:4,11,96`).
Firmowid is a useful behavioral reference but its audited lock has older Ash
`3.27.7` and AshPostgres `2.9.1` (`firmowid/mix.lock:7,16`). AshBackpex `0.1.12`
pins Backpex `0.19.6` and requires the already-compatible Ash/AshPhoenix
range. Authentication, actor propagation, stale-safe sealed draft/manual pending alias/retailer create-edit, listing/mapping/history and card-set/card/valuation inspection, reasoned stale-safe sealed-listing and Cardmarket card-mapping correction, immutable decision history, typed canonical manual acquisition refresh, private-field deselection, stable one-column pagination, assets, routing, and mobile rendering are validated in TCG Cheap; broader resource coverage remains unresolved.

## Implications for subsequent phases

1. Model the MVP around `TcgCheap.Core` while keeping resources and actions
   feature/domain-first; the domain is intentionally empty today
   (`tcg-cheap/lib/tcg_cheap/core.ex:1-13`).
2. Keep public catalogue and pricing reads anonymous and policy-controlled. Add
   authentication and authorization before exposing any admin mutation or
   operations route; the MVP has no public accounts or marketplace.
3. Define provider contracts and failure/retry semantics before source adapters;
   use Req boundaries rather than coupling resources to HTTP details.
4. Add jobs only for demonstrated asynchronous work, with explicit
   provider/source/resource IDs, queue policy, and worker tests; use a scoped
   system actor only where authorization benefits.
5. Keep AshBackpex for ordinary main CRUD after the completed compatibility slice;
   retain focused authenticated LiveViews for evidence review and operational controls
   that cannot be expressed safely or clearly as generic CRUD.
6. Preserve LiveView UX and current local/devenv operations. The initial pinned
   release image, release commands, liveness/readiness boundary, and deployment/
   operations runbook are selected; production topology, restore evidence, and
   monitoring integration still need real deployment validation.

## Unresolved items

- The bounded provider/source experiment batch and cost/control analysis are recorded
  in the provider ADR, with metadata and sealed source direction established.
  Acquisition access is no longer vetoed under the scrappy policy, but exact
  seller-identity/destination capability validation remains unresolved, so Phase 0
  and provider locking are incomplete. Older access-first wording above is
  historical/stale.
- Remaining AshBackpex resource rollout, storage provider, and final production deployment
  topology need decisions. A pinned non-root OTP image, forward migration and one-shot administrator
  release commands, separate liveness/readiness endpoints, and deployment/operations runbook now exist and
  have been locally container-verified, but no production deploy or restore drill is claimed. Administrator
  password authentication, the sealed-product/alias/retailer/listing/
  mapping/history and card-set/card/valuation inspection slices, and existing background dependency versions
  are selected and validated. Typed canonical refresh/requeue for NBP, exact local Singles valuations, configured
  active sealed retailers, and reasoned card external-mapping correction with immutable history are also validated.
  Normalized TCGdex/sealed-source import issues and exact read-only buying-model policy are inspectable in the
  authenticated admin surfaces. Active source probes/alerts, arbitrary retained-job replay, production topology,
  and the remaining broader workflows stay open.
- Do not introduce multitenancy absent a demonstrated requirement. Decide the
  worker authorization/scope shape alongside the product resources.

## See Also

- [Provider and Acquisition Feasibility](provider-acquisition-feasibility.md)
