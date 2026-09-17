# CasC Demo — Session Notes

Knowledge capture from the session that stood up two parallel CloudBees CI demo stacks
(CasC-driven vs. no-CasC) to compare configuration-delivery mechanisms, iterated both to a fully
working state, and then tore both down. Both AWS environments described here are **currently
destroyed** — this file is a runbook/reference for standing them back up, not a description of
live infrastructure.

## The two stacks

| | `terraform-aws-ec2-cloudbees-ci-traditional` (this repo) | `terraform-aws-ec2-cloudbees-ci-traditional-no-casc` (sibling repo) |
|---|---|---|
| Config delivery | CasC bundles (`casc/cjoc/*`, `casc/controllers/{base,controller}/*`) via git, branch `casc-demo` | No CasC bundle at all — Groovy `init.groovy.d` scripts + REST APIs, generated during Terraform apply |
| OC URL | `oc.training.swen.aws.ps.beescloud.com` | `oc-nc.training.swen.aws.ps.beescloud.com` |
| CM URL | `cm.training.swen.aws.ps.beescloud.com` | `cm-nc.training.swen.aws.ps.beescloud.com` |
| CM sizing | Single node (`max_size=1`) — HA not needed for this demo | Single node (`max_size=1`) |
| Credentials | `admin` / `admin` (default, unchanged in `.auto.tfvars`) | `admin` / `admin` |
| AWS | `AWS_PROFILE=324005994172_infra-admin`, `us-east-1`, `TF_CLI_CONFIG_FILE=$(pwd)/.terraformrc.local` needed for `terraform init` (direct provider install, no mirror) | same |

The no-CasC repo's plan document lives at `/Users/holywen/.claude/plans/jolly-chasing-moon.md`.

## `casc-demo` branch (this repo)

Created specifically so the CasC bundle's git-backed SCM retriever could be scoped to one branch
instead of tracking `main`. Key commits, oldest first:

1. `570f05a` — resize `cm_asg` to `max_size=1` (no HA needed for this demo).
2. `b2db2e0` — restrict the CJOC controller-bundle SCM retriever to `casc-demo` only via a
   `headRegexFilter` trait (alongside `gitBranchDiscovery`), and point the `ha` clientController
   item's `configurationAsCode.bundle` at `casc-demo/controller` instead of `main/controller`.
3. `20ac4fb` — **real bug fix**: `oc.tpl`'s `git clone` was still pulling the repo's *default*
   branch (`main`) for OC's own `occascbundle` files (items/plugins/rbac/bundle.yaml). Only the
   downstream *controller* bundle retriever was scoped to `casc-demo` — OC's own bundle wasn't,
   so the persisted `ha` item kept `<bundle>main/controller</bundle>` even after `casc-demo`'s
   `items.yaml` was updated. Fixed by adding `-b casc-demo` to the clone.
4. `8456de8` / revert `255e78d` — proved out `automaticReload`/`automaticRestart` by pushing a
   header-label text change; **reverted after the test**, not left in the branch.
5. `0e1a4d3` / revert `255e78d` — added then reverted a `test-agent1` pipeline (same
   verify-then-revert pattern) to confirm item-level bundle updates.

**Net effect for future runs:** `casc-demo` currently matches `main` except for the branch
restriction + bundle-path change (commits 2–3). No demo pipelines were left behind.

## What we learned about CasC bundle behavior (verified live, not from docs)

- **`unclassified`/`jenkins:` (jcasc) changes hot-reload.** Pushing a change to `jenkins.yaml`
  propagates: OC's `bundleStorageService` retriever polls every `pollingPeriod` (120s in this
  bundle) → picks up the git change → pushes it to the connected controller → controller
  reprocesses its CasC config (`i.j.p.casc.BaseConfigurator` reruns) within a few seconds.
  Confirmed via a header-label text change: detected ~2 min after push, applied ~3s after OC's
  own checkout completed.
- **`items:` changes do NOT hot-reload**, even with `automaticReload: true` /
  `automaticRestart: true` set. `ItemsProcessor#create` only runs once, at controller boot.
  Pushing a new/changed item to git gets picked up by OC's retriever (visible in OC's log,
  `Bundle .../base checked out successfully`) but the controller's job list does not change
  until the controller is restarted. Fix: after pushing an items change, trigger
  `POST {cm_url}/safeRestart` (with a crumb) to force reprocessing.
- **`/configuration-as-code/export`** (the vanilla open-source `configuration-as-code` plugin's
  endpoint) **never includes `items:` or `rbac:`**, regardless of which plugins are installed —
  confirmed by checking this reference stack's own OC, which has a full working CasC bundle.
  It only covers the `jenkins:`/`unclassified:`/`security:`/`credentials:` JCasC domain.
- **Full bundle export (with items/rbac) lives at CloudBees-specific endpoints**, exposed by the
  UI page **Manage Jenkins → CloudBees Configuration as Code export and update**:
  - `GET /core-casc-export/jenkins.yaml`
  - `GET /core-casc-export/items.yaml`
  - `GET /core-casc-export/rbac.yaml`
  - `GET /core-casc-export/plugins.yaml`
  - `GET /core-casc-export/bundle.yaml`
  - `GET /core-casc-export/full-export` (zip)
  - UI page itself: `/casc-bundle-export-ui/`
  - Individual item export (from a job's own dashboard, "Export CasC item" task link):
    `POST /job/<name>/export` → redirects to the rendered `items.yaml` snippet for just that job.
- **Plugins required for the full bundle export to work** (confirmed by diffing a working
  CasC-bundle OC/CM against a from-scratch instance that had only the default envelope):
  - OC: `cloudbees-casc-items-api`, `cloudbees-casc-items-commons`, `cloudbees-casc-items-server`,
    `cloudbees-casc-client`, `configuration-as-code` (`operations-center-rbac` is already in the
    default OC envelope).
  - Controller: `cloudbees-casc-items-api`, `cloudbees-casc-items-commons`,
    `cloudbees-casc-items-controller`, `cloudbees-casc-client`, `configuration-as-code`
    (`nectar-rbac` is already in the default controller envelope).
  - Per CloudBees docs, RBAC-aware item export additionally needs: OC → **Operations Center
    Server Role Based Access Control** plugin (`operations-center-rbac`); controller →
    **CloudBees Role-Based Access Control** plugin (`nectar-rbac`). Both already present by
    default, so only the `casc-items-*`/`configuration-as-code`/`casc-client` plugins were
    actually missing on a from-scratch (no-CasC) instance.
- **A connected controller's `rbac.yaml` export stays empty unless it's actually linked to OC's
  RBAC**, which requires the controller's `securityRealm` to be `operationsCenter` ("Single
  Sign-On via Operations Center", class
  `com.cloudbees.opscenter.client.plugin.OperationsCenterSsoSecurityRealm`) *and*
  `authorizationStrategy` = `cloudBeesRoleBasedAccessControl`
  (`nectar.plugins.rbac.strategy.RoleMatrixAuthorizationStrategyImpl`) — confirmed via this
  reference CM's own `/configuration-as-code/export` (`securityRealm: "operationsCenter"`,
  `authorizationStrategy: "cloudBeesRoleBasedAccessControl"`). OC additionally needs
  `unclassified.operationsCenterSharedConfiguration.enabled: true` for the RBAC sync itself to
  run (a `ConfigurationRefresher` polls every 60s once enabled).

## GitOps proposal discussed (not yet implemented)

Controller-side bundle updates already form a working GitOps loop (push → poll → reload, see
above). OC's *own* bundle does not, because `oc.tpl` renders `jenkins.yaml` locally via Terraform
(secrets substituted at instance-creation time) and only does a one-time `git clone` for the
other three files — a bundle change requires replacing the EC2 instance to take effect.

Recommended fix (see full write-up in conversation history): move OC's secrets
(`oc_login_user`/`oc_login_pwd`/`oc_url`) out of Terraform-time `${...}` interpolation and into
CasC-native `${ENV_VAR}` resolution sourced from `/etc/sysconfig/cloudbees-core-oc`, so
`jenkins.yaml` becomes a static, git-trackable file like the other three. Then give OC's own
bundle the same SCM-retriever treatment already used for `controller_bundles`, instead of a
boot-time-only local copy. Net result: push to `casc-demo` → both OC and the controller reload
within ~2 minutes, no instance replacement. Trade-off: `automaticRestart: true` means an OC outage
window for changes that require a restart (security realm/authz changes); JCasC-only changes
still hot-reload with no interruption.

## Sibling no-CasC repo — key bugs found and fixed (summary; full detail in that repo's README)

All discovered by `javap`-inspecting the actual installed plugin jars, since the public CloudBees
KB scripts / doc examples were stale relative to CBCI 2.492.2.3:

- `RoleMatrixAuthorizationStrategyImpl.getInstance()` returns `null` until already active — must
  construct with `new`, not call the static accessor.
- License activation requires `hudson.license.LicenseManager.setLicense(key, cert, true)` via
  Groovy — dropping `license.key`/`license.cert` files alone is not sufficient (that's what the
  CasC `license:` block itself was doing under the hood).
- `com.cloudbees.opscenter.server.jnlp.slave.JocJnlpSlaveLauncher` (from the public CloudBees
  example script) doesn't exist on this CBCI version — replaced with core
  `hudson.slaves.JNLPLauncher` for the shared agent.
- `OperationsCenter.createClientcontroller()` (from the CloudBees KB article) doesn't exist —
  actual method is `createClientMaster()`.
- OC's own `unclassified.location.url` must be set explicitly, or the client-controller-attach
  script's derived `MASTER_OPERATIONSCENTER_ENDPOINT` resolves to `localhost:8888`.
- A pre-existing bug in the CM's `00-defaults.groovy.tpl` referenced two non-existent classes
  (`jenkins.model.JobBuildDiscarder`/`SimpleBuildDiscarder`) for a "default build discarder"
  setting; since Groovy compiles a whole script before running any of it, this silently killed
  the *entire* init script every boot (so `location.url`, header label, and — once added —
  `securityRealm`/`authorizationStrategy` never actually applied until this was removed).
- Accepted gaps that remain: 4 of 62 `administer`-role RBAC permissions
  (`com.cloudbees.plugins.updatecenter.UpdateCenter.{Upload,Configure,Store,Promote}`)
  consistently 500 on this envelope's RBAC REST API; the shared agent (`mySharedAgent`) is
  lease-provisioned rather than directly JNLP-connectable, so `agent1`'s connection to it is not
  fully equivalent to the CasC bundle's declared shared-agent item.

## Teardown performed

Both stacks were destroyed via `terraform destroy -auto-approve` (36 resources in the no-CasC
repo, 35 in this one) at the end of the session; both `terraform state list` outputs are empty.
No EC2 instances, ALBs, EFS, or Route53 records from either stack remain. (Two KMS keys still
show up under the shared `cb-user:swen` AWS tag — those belong to an unrelated pre-existing EKS
cluster, `cbcd-bp01/bp02-swen-demo-eks`, not to this work.)

## Redeploying

```bash
export AWS_PROFILE=324005994172_infra-admin
export AWS_DEFAULT_REGION=us-east-1
export TF_CLI_CONFIG_FILE="$(pwd)/.terraformrc.local"   # required: direct provider install, no local mirror

terraform init
terraform plan
terraform apply
```

Repeat in the sibling no-CasC repo with its own `.terraformrc.local`. Both repos' `.auto.tfvars`
already point at the `casc-demo`-scoped subdomains/branch described above.
