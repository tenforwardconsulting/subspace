# Server OS upgrade plan (`subspace upgrade`)

Design for a subspace command that replaces servers running an old Ubuntu release
with new servers built from a current AMI, without rebuilding the environment by
hand.

The workhorse and oxenwagen topologies need fundamentally different procedures:

| | workhorse | oxenwagen |
|---|---|---|
| web servers | 1 | N behind an ALB |
| workers | same server | separate instance(s) |
| database | postgres **on the box** | RDS (untouched by an OS upgrade) |
| redis | on the box | ElastiCache (untouched) |
| cutover | move the Elastic IP | register/drain ALB target group |
| downtime | maintenance window for the db copy | none, rolling |
| data migration | required (`pg_dump`/`pg_restore`) | none |

So the plan is: one command, one set of shared primitives, and **one strategy
object per template** that owns the actual sequence. Getting the strategy wrong
on a production database is the worst realistic failure mode, so strategy
selection is defended explicitly (see "Never run the wrong process").

Phase 1 of implementation is workhorse only. Oxenwagen is sketched here so the
shared primitives don't get shaped exclusively around the single-server case.

---

## 1. Terraform: keyed instances instead of a single instance

Numbered host slots (`production1`, `production2`, …) become `for_each` keys, so
every slot has a permanent terraform state address and nothing is ever renamed.

This change lands **upstream first**, as `terraform-subspace-workhorse v2.0.0`
(major: the variable interface changes). Subspace then bumps its pin in
`Init::TERRAFORM_MODULES`, so newly initialized projects vendor a module that
already supports upgrades and never need the migration in the next section. The
upgrade command's minimum supported module version is checked explicitly (see
"Compatibility check").

In the module: 

```hcl
variable "instances" {
  # key = host suffix.  production1 => "1"
  type = map(object({
    ami           = string
    instance_type = string
    volume_size   = number
  }))
}

variable "active_instance" { type = string } # which key owns the Elastic IP

resource "aws_instance" "single" {
  for_each      = var.instances
  ami           = each.value.ami
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.subspace.key_name
  vpc_security_group_ids = [aws_security_group.single.id]

  tags = {
    Name        = "${var.project_name} ${var.project_environment}${each.key} Server"
    Environment = var.project_environment
  }
  root_block_device { volume_size = each.value.volume_size }
}

resource "aws_eip_association" "eip_assoc" {
  allocation_id = aws_eip.single.id
  instance_id   = aws_instance.single[var.active_instance].id
}
```

Three notes:

- **Drop `instance = aws_instance.single.id` from `aws_eip.single`.** Today the
  module sets the association both inline on the EIP and via
  `aws_eip_association`, which is a latent conflict. The cutover is built on the
  association resource, so the inline attribute must go or applies become
  unpredictable.
- The EIP itself is never replaced, so the Route53 A record never changes and the
  Let's Encrypt certificate stays valid for the same address. **No DNS work in
  the cutover at all.**
- `output "inventory"` iterates the same map, so `subspace tf` writes both hosts
  into `inventory.yml` with the same groups — the new server inherits
  `group_vars/<env>` and the vault secrets with zero duplicated config. This is
  the main reason the upgrade lives in the existing env rather than a parallel
  `production_upgrade` terraform directory.

### Compatibility check, and migrating existing projects

Existing projects are in wildly varying states: module referenced by git URL
rather than vendored, vendored but locally modified, vendored at an old ref, or
config hand-written years ago. Trying to automatically rewrite all of those is
where this feature would go wrong, so **subspace detects and instructs rather
than migrates.**

`subspace upgrade <env> --check` (also run as the first step of every other
phase, non-skippably) verifies:

1. The env's module source resolves to a workhorse module at **>= v2.0.0** —
   read from the vendored `module.yml` manifest if the source is local, or from
   the `?ref=` in the git URL if it's remote.
2. The module exposes `variable "instances"` and `variable "active_instance"` —
   a direct check against the actual source, which catches a locally modified
   vendored copy whose manifest lies.
3. `terraform state list` contains keyed instances (`aws_instance.single["1"]`),
   not the legacy unkeyed `aws_instance.single`.
4. `terraform plan` is empty, so the config and the real infrastructure agree
   before anything is built. An upgrade started from a dirty plan inherits
   whatever drift is already there.

Any failure aborts and prints the specific remediation, e.g.:

```
This environment is on terraform-subspace-workhorse v1.1.0 (needs >= v2.0.0).

To migrate (one time, ~5 minutes, no downtime):

  1. Re-vendor the module:
       subspace upgrade production --revendor      # clones v2.0.0, keeps a .bak
  2. In config/subspace/terraform/production/main.tf replace
       instance_ami = "ami-0abc..."
       instance_type = "t3.medium"
       instance_volume_size = 20
     with
       instances = { "1" = { ami = "ami-0abc...", instance_type = "t3.medium", volume_size = 20 } }
       active_instance = "1"
  3. Move the existing instance into its new state address:
       terraform state mv 'module.workhorse.aws_instance.single' 'module.workhorse.aws_instance.single["1"]'
  4. terraform plan   # MUST show "No changes".  If it shows a replacement, stop
                      # and ask — do not apply.
```

Step 1 is automated (`--revendor` is a safe file operation) and steps 2-4 are
manual, because step 3's exact address depends on the module block's name and
step 4 is a judgment call. If a project's vendored module is unmodified from a
known upstream ref, `--revendor` can also offer to apply step 2 for them; it
refuses on any locally modified module. The `terraform plan` gate is
non-negotiable in either path — a plan that proposes replacing the running
instance means the migration is wrong, and applying it would destroy the
production server and its database.

`--init` then records `phase: initialized` in `upgrade.yml` only after `--check`
passes cleanly.

---

## 2. Command surface

```
subspace upgrade <env> --init       # one-time: migrate tf config + state to keyed slots
subspace upgrade <env> --status     # where am I in the upgrade?  what's next?
subspace upgrade <env> --prepare    # build + bootstrap + provision the new slot
subspace upgrade <env> --copy-db    # open the maintenance window, copy the db across
subspace upgrade <env> --cutover    # move traffic, close the window
subspace upgrade <env> --finalize   # destroy the old slot, clean up config
subspace upgrade <env> --abort      # back to the old slot (pre-cutover only)
```

Deliberately **not** one long-running command. Each phase ends at a point where
it's safe to walk away for hours, and the manual verification and deploy steps
happen between phases. Resumability matters more than automation here.

The maintenance window spans two commands rather than one, because the most
valuable verification in the whole process is only possible in between them: the
new server running the **real** data, on its own address, while nothing is writing
to either database. A single `--cutover` would move the IP seconds after the copy
finished, which means the first real look at the migrated data happens when it is
already live.

### State tracking

Phase state lives in `config/subspace/terraform/<env>/upgrade.yml` (committed):

```yaml
template: workhorse
started_at: 2026-09-18T10:00:00Z
from_slot: "1"
to_slot: "2"
from_ami: ami-0abc...      # for the record
to_ami: ami-0def...
ubuntu_release: noble
phase: prepared            # initialized | prepared | copied | cutover | finalized
window_open: false         # is the old server stopped behind the maintenance page?
log:
  - { phase: prepared, at: 2026-09-18T10:42:00Z }
```

Every phase asserts the expected predecessor phase and aborts otherwise, so
`--cutover` can't run before `--copy-db`, and `--prepare` can't be run twice and
silently build a third server.

---

## 3. Workhorse procedure

### `--prepare`

1. Assert clean git working tree in the project (config changes must be
   committable and reviewable) and `phase: initialized`.
2. **Require that the operator has taken a full database backup off the old
   server, before anything else** — a prompt, not an action. It is the only
   artifact that survives every possible mistake in the rest of the process,
   including a mistaken `terraform apply` that destroys the wrong instance, which
   is exactly why subspace does not take it: a dump nobody has restored is not a
   backup, and verifying it means loading it into a local database that only the
   operator has. Subspace takes one dump of its own, at `--finalize`, because
   that one is otherwise lost forever the moment the instance is destroyed.
3. Resolve the target AMI: reuse the `aws ec2 describe-images` lookup from
   `Init#set_latest_ami`, with the Ubuntu release name as a parameter
   (`--ubuntu-release noble`, or `--ami ami-...` to pin explicitly). Extract this
   out of `Init` into a shared `Subspace::Ami.latest(release:, profile:)`.
4. Pick the next slot key (`max(existing keys) + 1`) and add it to the
   `instances` map in the project's `main.tf`, copying instance type and volume
   size from the current active slot.
5. `terraform apply`. Show the plan and require confirmation; refuse to proceed
   if the plan touches anything other than creating the new instance (no
   replacement of the active instance, no EIP change).
6. `subspace tf` inventory merge adds `<env>2`. Add the `upgrade` group to that
   host in `inventory.yml` so it can be targeted independently of `<env>`.
7. `subspace bootstrap <env>2`.
8. `subspace provision <env>2` with the `letsencrypt` role skipped
   (`--skip-tags letsencrypt`) — HTTP-01 validation cannot succeed while the
   domain still resolves to the old server. The cert is copied at cutover
   instead.
9. Generate `config/deploy/<env>_upgrade.rb` from the `upgrade` group and print
   the deploy command.

Subspace never restores a dump onto a server. Pre-cutover verification runs
against the empty database that provision created; if realistic data is wanted
there, the operator can load it themselves. The only write of a database into a
server that this feature performs is the cutover copy, which is guarded by
`db_copy` refusing a destination that already holds data — so it cannot destroy
anything that was not built empty minutes earlier.

Then stop and tell the operator exactly what to do next:

```
Slot 2 is provisioned at 54.12.34.56 (ami-0def..., ubuntu noble).

  1. bundle exec cap production_upgrade deploy
  2. Verify the app: ssh in, check logs, hit the server directly
  3. subspace upgrade production --copy-db

The old server is still serving all traffic.  Nothing is at risk yet.
```

### `--copy-db`

Opens the maintenance window and moves the data. Requires `phase: prepared`, and
every step is abortable — the Elastic IP does not move here.

1. Re-verify: new slot reachable over ssh, puma responding locally on the new
   box, app version present. Refuse if the app was never deployed there.
2. `subspace maintenance_mode --on --limit <env>1` — **always `--limit`**; the
   new host shares the `<env>_web` group, so an unlimited call would take down
   the server you are about to cut over to.
3. Assert the old server actually returns the 503 maintenance page for its own
   `server_name`. "Maintenance mode is on" is not the same claim: the
   `nginx-maintenance` role copies the page out of the deployed release, and does
   nothing at all when the app ships no `public/maintenance.html`.

   Deliberately **before** step 4 rather than after. Nginx returns the 503 on the
   file's existence alone, so puma being up or down doesn't change the answer — but
   it does change the cost of the check failing. Checked here, a project with no
   maintenance page fails with its site still fully up and serving; checked after,
   the same project fails with puma stopped and nothing to show users.
4. Stop puma and the worker processes on the old server (quiesce writes; a
   maintenance page alone does not stop background jobs).
5. Copy `/etc/letsencrypt` from old to new, so TLS works the instant the IP
   moves and certbot just renews on its normal schedule.
6. Set `allow_instance_ssh = true` and `terraform apply` (apply 1) — opens the
   instance-to-instance ssh path for the copy only.
7. `subspace db_copy --from <env>1 --to <env>2` (section 4), with no `--force`:
   steps 2-4 established exactly the state its guards check for, so forcing them
   would only hide a step that didn't work.
8. Set `allow_instance_ssh = false` and `terraform apply` (apply 2), closing the
   temporary rule as soon as the copy is done rather than leaving it open for the
   length of the verification window.
9. Record `phase: copied` and print the new slot's public address.

Then stop. The new server is now running the real production data and is reachable
on its own address; the old one is stopped behind the maintenance page and nothing
is writing to either database. This is the state the whole two-phase split exists
to create, and it can be held for as long as the maintenance window allows:

```
production-app2 has production's data and is running at https://54.12.34.56/

  1. Verify it against the real data (curl -k; the cert is for the domain)
  2. subspace upgrade production --cutover   # move the elastic IP
     subspace upgrade production --abort     # or back out to production-app1
```

### `--cutover`

Moves the Elastic IP and nothing else. Requires `phase: copied`.

1. Flip `active_instance` to the new key and `terraform apply`. DNS is untouched
   and re-association takes seconds.
2. Record `phase: cutover` immediately, as soon as the IP has moved — see "There
   is no rollback after cutover".
3. Health check the public address until it returns 200 (bounded retry).
4. Assert the new server is **not** in maintenance mode. Correct, it never was —
   this is a check, not an action, guarding against a half-finished earlier run
   or a maintenance flag that came along with a copied file. Cheap, and the
   failure it catches (site stuck on the maintenance page after a "successful"
   cutover) is otherwise confusing to diagnose.

The old server stays stopped and in maintenance mode. That is deliberate: it keeps
its database exactly as it was at the copy, and a second server that starts serving
the same app on a stale database is a worse outcome than one that is plainly down.

### There is no rollback after cutover

`--abort` is the whole recovery story, and it stops at the EIP flip.

The realistic reasons to want to go back are the database copy failing, or the
copied data not looking right — and both of those land in `phase: copied`, before
the IP has moved, while `--abort` still applies and the old server still holds the
only copy of the data. That is exactly what the `--copy-db` / `--cutover` split is
for: it puts the decision point *before* the irreversible step rather than after
it. So the cases worth automating are covered by going forward or aborting, and
neither needs a rollback.

`--abort` therefore accepts `phase: prepared` or `phase: copied`. From `copied` it
starts puma and the workers back up on the old server and takes it out of
maintenance mode before destroying the new slot. Nothing has written to the old
database since `--copy-db` stopped it, so there is nothing to reconcile — which is
the whole reason the window stays open across the verification.

Past the flip, the new server is serving live traffic and holds the only current
copy of the data, which makes going back a *second migration* rather than an undo:
the data has to come back with it, or every write since cutover is silently lost.
That is a judgment call about real production data made under pressure, and the
right shape for it depends on what actually broke. Subspace doesn't guess — the
operator copies the data back with `subspace db_copy` and moves `active_instance`
by hand. `upgrade.yml` still records both slots and both AMIs, so the pieces are
there.

`phase: cutover` is recorded immediately after the flip, before the health check,
so that `--abort` can never be pointed at a server that is already live on the
elastic IP.

An interrupted `--copy-db` leaves `phase: prepared` with the old server quiesced,
so the window state is recorded as `window_open: true` in `upgrade.yml` *before*
the window opens rather than when the phase completes — `--abort` keys off that
flag, not off the phase, and so still knows to start the old server again. Re-running
`--copy-db` after a partial copy is not safe (the destination may now hold data, and
`db_copy` refuses that), so the recovery is `--close-instance-ssh` if the rule was
left open, then `--abort`, then start again from `--prepare`.

### `--finalize`

Separate and deliberate, so the old server stays up — with the data it had at
cutover — for as long as the team wants. Days is fine.

1. Require `phase: cutover` and a typed confirmation naming the instance to be
   destroyed.
2. Take a final `pg_dump` from the old server. This is the one dump subspace takes
   itself, because the instance is about to be irrecoverable and nothing else
   captures what was written between prepare and cutover. The operator's own
   pre-`--prepare` backup is still the primary safety net.
3. Remove the old key from the `instances` map, `terraform apply`.
4. Remove the old host from `inventory.yml`; drop the `upgrade` group from the
   new host; delete `config/deploy/<env>_upgrade.rb`.
5. Set `phase: finalized` and print the config diff to commit.

---

## 4. `subspace db_copy`

A first-class subspace command rather than a jefferies_tube capistrano task:
this is a host-to-host infrastructure operation, and capistrano tasks act on one
stage at a time, so a cross-host copy doesn't fit that model. Subspace already
has both hosts, their ssh credentials, and the database credentials in
`inventory.yml` + `group_vars` + vault.

```
subspace db_copy --from production1 --to production2
```

Implemented as an ansible playbook (`ansible/playbooks/db_copy.yml`) so
`database_name`, `database_user`, and `database_password` come from the existing
group_vars/vault rather than being re-parsed in Ruby.

- `pg_dump -Fc --no-owner --no-acl` on the source → `pg_restore --clean
  --if-exists` on the destination. Provision already creates the role and the
  empty database on the new host, so `--no-owner` restores cleanly without
  touching roles or passwords.
- Print both servers' `SELECT version()` before starting, so a major postgres
  version jump is visible before it's committed to.
- Refuse unless the source is in maintenance mode with puma and the workers
  stopped, unless `--force`.
- Refuse if the destination database contains data, unless `--force`.
- Report row counts for the largest tables on both sides afterward as a
  smoke-test of completeness.

### Transport: stream directly between the servers

Direct server-to-server is the right default, and it's not much work. Both
instances are in the same VPC and share one security group, so the bytes can go
over the private network at instance-bandwidth speed instead of through the
operator's uplink. Two things are needed:

**1. A temporary security group.** The workhorse SG currently allows port 22 only
from `var.ssh_cidr_blocks`, so the servers can't ssh to each other. Add a
self-referencing rule that is **off by default and only open during the copy**:

```hcl
variable "allow_instance_ssh" {
  description = "Temporarily allow ssh between instances in this group.  Used by subspace upgrade for the db copy; should be false at rest."
  type        = bool
  default     = false
}

resource "aws_security_group" "instance_ssh" {
  count       = var.allow_instance_ssh ? 1 : 0
  name        = "${var.project_name} ${var.project_environment} instance ssh"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.single.id]
  }
}

# in aws_instance.single
vpc_security_group_ids = concat(
  [aws_security_group.single.id],
  aws_security_group.instance_ssh[*].id
)
```

This is a whole second group rather than an
`aws_vpc_security_group_ingress_rule` added to `aws_security_group.single`,
because that group uses inline `ingress` blocks and the AWS provider refuses to
mix the two forms — it reconciles the inline set on every apply and deletes any
rule it doesn't own, so the toggle would silently close itself. The second group
also means `aws_security_group.single` is never touched, so no existing
environment sees a security group diff when it re-vendors. Toggling the variable
creates or destroys the group and updates each instance's group list in place; no
instance is replaced.

Ships in the same `v2.0.0` module release, defaulting to closed, so no existing
environment's exposure changes by adopting it. The upgrade drives the toggle:

- `--copy-db` sets `allow_instance_ssh = true` and applies **immediately before**
  `db_copy`, then sets it back to `false` and applies again as soon as the copy
  finishes. Both applies are within that one phase, so the rule is never open
  across the verification window, however long that window is held open.
- `--cutover`'s apply only moves the EIP. All three applies are seconds long — SG
  rule changes and EIP re-association modify in place, no instance is touched.
- Every phase and `--check` assert the rule is closed at rest and refuse to
  proceed while it's open (outside the copy window), printing the one-line fix.
  An interrupted `--copy-db` is the realistic way it gets left open, so `--status`
  reports it prominently and `--close-instance-ssh` exists as an explicit repair.

Even while open it grants only instance-to-instance access within the group, but
"temporary and asserted closed" is the right posture for a rule that exists
solely for a five-minute window.

**2. Agent forwarding, not a deployed key.** Run the pipe from the source host
with the operator's forwarded agent:

```
ssh -A <old> 'pg_dump -Fc --no-owner --no-acl <db> | ssh <new-private-ip> "pg_restore ..."'
```

No permanent server-to-server credentials are created, nothing needs cleanup
afterward, and the operator's machine carries only the control connection. The
private IP comes from terraform output, so it's already known.

Fall back to `--via-local` (`ssh src pg_dump | ssh dst pg_restore`, everything
through the operator's machine) when agent forwarding isn't available or the two
hosts genuinely can't reach each other — e.g. the oxenwagen case later, or a
project pinned to an older module without the SG rule. The command detects the
SG rule's absence and says which mode it's using and why, rather than silently
choosing the slow path.

For oxenwagen this whole section is moot: RDS isn't rebuilt, so there's no copy.

---

## 5. Code deploy stays manual

Subspace does not deploy. Deploys need a git ref, asset builds, and
project-specific hooks that capistrano and jefferies_tube own; shelling into
them would couple two gems' release cycles for no real gain.

What subspace *does* automate is the stage config, which is nearly free —
`Subspace::Commands::Inventory#capistrano_deployrb`
(`lib/subspace/commands/inventory.rb:33`) already generates the `server` lines.
Two changes needed:

- add `--output PATH` so it can be called non-interactively (it currently prints
  to stdout)
- emit `set :rails_env, '<env>'` explicitly. The stage is named
  `production_upgrade`, so any `deploy.rb` that infers `rails_env`, the deploy
  path, or the branch from the stage name would otherwise point the new server at
  the wrong environment.

Everything else is a printed command and a "press enter when done" prompt.

---

## 6. Never run the wrong process

A workhorse cutover on an oxenwagen environment would take an ALB fleet down and
attempt a `pg_dump` against a host with no local postgres. Three independent
defenses:

**1. Recorded template.** `--init` writes `template: workhorse` into
`upgrade.yml`, sourced from the vendored module directory (fold the
`SUBSPACE_MODULE_VERSION` file that `init` currently writes into a proper
`module.yml` manifest: template, repo, ref). The template is never inferred from
a flag or a guess at runtime.

**2. State fingerprint cross-check.** Before any phase runs, the strategy
asserts its own signature against `terraform state list`:

- workhorse requires `aws_instance.single`, and requires the **absence** of
  `aws_lb` and `aws_db_instance`
- oxenwagen requires `aws_lb`, `aws_db_instance`, `aws_instance.web`

If the recorded template and the state fingerprint disagree, abort with both
values printed and no further action. This catches a hand-edited manifest, a
copied config directory, and an env that was migrated between templates.

**3. Strategy objects, not conditionals.** The strategy is resolved once, at the
top:

```ruby
Subspace::Upgrade::STRATEGIES = {
  "workhorse" => Subspace::Upgrade::Workhorse,
  "oxenwagen" => Subspace::Upgrade::Oxenwagen,
}
```

Each strategy implements `init/prepare/copy_db/cutover/finalize/abort` and
`state_signature`. There is no `if template == "workhorse"` inside shared code —
so a shared helper can't silently do the wrong topology's work, and an
unrecognized template raises instead of falling through to a default. Every
destructive step also prints the resolved template and the instance IDs it is
about to act on, so a wrong process is visible in the confirmation prompt, not
only in the outcome.

---

## 7. Oxenwagen sketch (phase 2, not built yet)

Recorded now mainly to keep the shared primitives honest.

The OS upgrade is *easier* here, because the stateful services are managed: RDS
and ElastiCache are not touched, so **there is no data migration and no
maintenance window.** (An RDS engine-version upgrade is a separate concern and
should be a separate command; it must not be bundled into the OS upgrade.)

Rough shape — rolling replace, not blue/green:

1. Web tier: `aws_instance.web` uses `count` today. Convert to keyed `for_each`
   with a per-slot AMI, same as workhorse, so a new-AMI instance can exist
   beside the old ones.
2. Add new web instances with the new AMI, bootstrap, provision, deploy.
3. Register the new instances in the ALB target group; wait for healthy.
4. Deregister the old instances, wait for connection draining.
5. Destroy the old web instances.
6. Worker tier separately: stop workers on the old instance (let in-flight jobs
   finish), provision and deploy the new one, start workers there, destroy the
   old. Needs care with any singleton/cron-like job so it doesn't run in two
   places or in neither.

Reused from workhorse: AMI lookup, `instances` map editing, tf apply wrapper with
plan review, inventory manipulation, cap stage generation, `upgrade.yml` phase
tracking, health checks. Not reused: cutover mechanism, `db_copy`, maintenance
mode (the whole point is that there isn't a window).

---

## 8. Build order

1. `Subspace::Ami.latest` extracted from `Init#set_latest_ami`; `module.yml`
   manifest replacing `SUBSPACE_MODULE_VERSION`.
2. Workhorse module: keyed `instances` map, `active_instance`, EIP association
   fix, `allow_instance_ssh` toggle (default false), inventory output. Tag
   upstream `v2.0.0` and bump the pin in `Init::TERRAFORM_MODULES`.
3. `subspace upgrade --check` / `--revendor` / `--init`: version and state
   detection, remediation output, zero-diff plan gate.
4. `inventory capistrano --output` + explicit `rails_env`.
5. `subspace db_copy` playbook and command, with its guards.
6. `subspace upgrade --prepare` / `--status`.
7. `subspace upgrade --copy-db`, then `--cutover` / `--abort`.
8. `subspace upgrade --finalize`.
9. Full dry run end-to-end against a throwaway dev environment, including an
   `--abort` from an open maintenance window, before any of it is pointed at
   production.
10. Oxenwagen strategy.

## Open questions

- Where does `upgrade.yml` live if a project uses Terraform Cloud? The phase
  state is local-file-based and assumes the operator's working copy is the
  source of truth; concurrent operators would conflict.
- Should `--prepare` snapshot the old root volume before `--finalize` destroys
  it, as a cheaper alternative to keeping the instance around?
- Ubuntu release naming: hardcode a known-good list (`noble`, `resolute`, …) or
  accept any string and let the AMI lookup fail? A typo silently matching no AMI
  and producing an empty `ami = ""` should be impossible.
