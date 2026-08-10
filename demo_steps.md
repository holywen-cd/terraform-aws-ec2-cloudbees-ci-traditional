# CloudBees CI HA Demo Steps

Environment: `training.swen.aws.ps.beescloud.com`
OC: https://oc.training.swen.aws.ps.beescloud.com
CM: https://cm.training.swen.aws.ps.beescloud.com

## Prerequisites (run once, in every terminal you use)

```bash
cd /Users/holywen/workspace/cloudbees/terraform-aws-ec2-cloudbees-ci-traditional
export AWS_PROFILE=324005994172_infra-admin
export AWS_DEFAULT_REGION=us-east-1
export TF_CLI_CONFIG_FILE="$(pwd)/.terraformrc.local"
```

**Important:** the `324005994172_infra-admin` profile's configured default region is `us-east-2`, but this environment lives in `us-east-1`. Without `AWS_DEFAULT_REGION=us-east-1` set, AWS CLI commands below will silently query the wrong region and return empty results (no error). Every `aws` command in this doc also passes `--region us-east-1` explicitly as a second layer of safety — keep that flag if you copy commands out of order.

SSH key for EC2 access: `c_swen-cdro-test1-64850d.pem` (in repo root, user `ec2-user`).

CM target group ARN (used throughout):
```
arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb
```

**Note:** instance IDs and public IPs shown in examples below will differ by the time you demo — always re-resolve them fresh right before you need them, using the commands provided.

---

## Demo 1: Rolling Upgrade (CloudBees CI software version)

**Story:** upgrade the CloudBees CI CM software version (RPM package) on each Client Controller node one at a time — via SSH/CLI, not Terraform — while the fleet keeps serving traffic. Verified end-to-end: 98/98 probes returned HTTP 200 (100% availability) across the full two-node upgrade from `2.492.2.3` → `2.528.1.29783`.

**Expected duration:** ~5-6 minutes per node (~10-12 min total for 2 nodes), plus ALB draining/health-check delays.

**Key idea:** never touch both nodes at once. For each node: pull it out of the ALB target group → stop the service → `dnf install` the new RPM version → start the service → verify locally healthy → put it back in the target group → wait for the ALB to confirm healthy → move to the next node.

### Step 0 — Resolve current CM node IDs and IPs (always do this fresh)

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names cm-server-asg-64850d \
  --query "AutoScalingGroups[0].Instances[*].InstanceId" --output text \
  --region us-east-1
```

For each ID returned, get its public IP:
```bash
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text \
  --region us-east-1
```

### Step 1 — Show the "before" state (current installed version on both nodes)

```bash
for ip in <NODE1_IP> <NODE2_IP>; do
  echo "--- $ip ---"
  ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@$ip "rpm -q cloudbees-core-cm"
done
```

### Step 2 — Start a continuous availability probe (separate terminal, leave running for the whole demo)

```bash
while true; do
  echo "$(date -u +%H:%M:%S)  HTTP $(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://cm.training.swen.aws.ps.beescloud.com/whoAmI/api/json)"
  sleep 3
done
```

This is the visual centerpiece — the audience watches `200` scroll continuously while nodes are upgraded one at a time underneath.

### Step 3 — (optional) Check what target version is available in the repo

```bash
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "sudo dnf --showduplicates list 'cloudbees-core-cm-*' 2>&1 | tail -20"
```

### Step 4 — Pull NODE1 out of the ALB target group

```bash
aws elbv2 deregister-targets \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --targets Id=<NODE1_INSTANCE_ID>,Port=8080 \
  --region us-east-1
```

Confirm it's draining (the other node stays `healthy` and keeps serving):
```bash
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table \
  --region us-east-1
```

### Step 5 — THE UPGRADE: stop, install, start, on NODE1

```bash
# stop the old version
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "sudo systemctl stop cloudbees-core-cm; sudo systemctl is-active cloudbees-core-cm"

# install the target version (dnf handles it as an in-place upgrade + old-version cleanup)
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "sudo dnf install -y cloudbees-core-cm-<TARGET_VERSION>"

# start the new version
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "sudo systemctl start cloudbees-core-cm; sleep 3; sudo systemctl is-active cloudbees-core-cm"
```

Narrate this out loud — this is the actual software version upgrade moment. Point out in the `dnf install` output: `Upgrading: cloudbees-core-cm-<new>` followed by `Cleanup: cloudbees-core-cm-<old>` — it's a real in-place upgrade, not a fresh install.

### Step 6 — Wait for JVM warmup, then verify locally before re-admitting traffic

```bash
sleep 60
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "curl -s -o /dev/null -w 'local HTTP %{http_code}\n' --max-time 5 http://localhost:8080/whoAmI/api/json; rpm -q cloudbees-core-cm"
```

Optional: tail the CBCI log and point out the upgrade-specific log lines proving Jenkins detected a real version upgrade (not a fresh install):
```bash
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<NODE1_IP> \
  "sudo grep -i 'InstallState\$Upgrade\|IdStoreMigrator\|fully up and running' /var/log/cloudbees-core-cm/cloudbees-core-cm.log | tail -5"
```

### Step 7 — Re-register NODE1 into the ALB target group

```bash
aws elbv2 register-targets \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --targets Id=<NODE1_INSTANCE_ID>,Port=8080 \
  --region us-east-1
```

Wait for the healthy-threshold to confirm it (3× 30s checks ≈ 90-100s):
```bash
sleep 100
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State}" \
  --output table \
  --region us-east-1
```

### Step 8 — Repeat Steps 4-7 for NODE2

Same commands, swap in NODE2's instance ID and IP. The audience sees the exact same pattern — drain, upgrade, verify, re-admit — reinforcing that this is a repeatable, one-node-at-a-time procedure.

### Step 9 — The punchline: confirm both nodes on the new version, zero downtime throughout

```bash
for ip in <NODE1_IP> <NODE2_IP>; do
  echo "--- $ip ---"
  ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@$ip "rpm -q cloudbees-core-cm"
done
```

Scroll back through the Step 2 terminal — no gap, no non-200 line, from start to finish.

---

## Demo 2: Pipeline Failover

**Story:** kill the CM node running a pipeline mid-build; the ALB reroutes traffic, the build finishes successfully anyway, and no data is lost.

**Expected duration:** ~5-8 minutes (90s build + ~90s failure detection + ~100s recovery detection).

### Step 1 — Create the demo pipeline job (one-time setup; skip if `failoverDemo` already exists)

Check first by opening `https://cm.training.swen.aws.ps.beescloud.com/job/failoverDemo/` in a browser. If it 404s, create it:

```bash
cat > /tmp/failover-job-config.xml << 'XMLEOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Failover demo: prints controller hostname, runs 90s</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>pipeline {
    agent any
    stages {
        stage('Run') {
            steps {
                script {
                    def hostname = InetAddress.getLocalHost().getHostName()
                    echo "Running on controller hostname: ${hostname}"
                }
                sh '''
                    start_time=$(date +%s)
                    while [ $(($(date +%s) - start_time)) -lt 90 ]; do
                        echo "Running... $(($(date +%s) - start_time))s elapsed on $(hostname)"
                        sleep 5
                    done
                '''
            }
        }
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XMLEOF

CRUMB=$(curl -sk -u admin:admin -c /tmp/jc.txt https://cm.training.swen.aws.ps.beescloud.com/crumbIssuer/api/json | python3 -c "import json,sys; print(json.load(sys.stdin)['crumb'])")

curl -sk -u admin:admin -b /tmp/jc.txt -X POST \
  -H "Jenkins-Crumb: $CRUMB" -H "Content-Type: application/xml" \
  --data-binary @/tmp/failover-job-config.xml \
  -w "HTTP %{http_code}\n" \
  'https://cm.training.swen.aws.ps.beescloud.com/createItem?name=failoverDemo'
```

### Step 2 — Trigger the build

```bash
CRUMB=$(curl -sk -u admin:admin -c /tmp/jc.txt https://cm.training.swen.aws.ps.beescloud.com/crumbIssuer/api/json | python3 -c "import json,sys; print(json.load(sys.stdin)['crumb'])")

curl -sk -u admin:admin -b /tmp/jc.txt -X POST \
  -H "Jenkins-Crumb: $CRUMB" \
  -w "HTTP %{http_code}\n" \
  'https://cm.training.swen.aws.ps.beescloud.com/job/failoverDemo/build?delay=0sec'
```

For a live audience, clicking **Build Now** in the browser UI on the `failoverDemo` job page reads better than raw curl.

### Step 3 — Watch it running

Browser (best for an audience): `https://cm.training.swen.aws.ps.beescloud.com/job/failoverDemo/lastBuild/console`

Or via CLI:
```bash
curl -sk -u admin:admin --max-time 5 https://cm.training.swen.aws.ps.beescloud.com/job/failoverDemo/lastBuild/consoleText
```

### Step 4 — Resolve the controller hostname printed in the console to a public IP

The console output prints the **internal** hostname/IP (e.g. `Running on controller hostname: ip-10-0-1-134.ec2.internal`) — that's not reachable directly for SSH. Resolve it to the instance and its public IP:

```bash
aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=ip-10-0-1-134.ec2.internal" \
  --query "Reservations[0].Instances[0].{Id:InstanceId,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress}" \
  --region us-east-1
```

Swap in whatever hostname the console actually printed. If the console printed a bare private IP instead of a hostname, filter on `private-ip-address` instead:

```bash
aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=10.0.1.134" \
  --query "Reservations[0].Instances[0].{Id:InstanceId,PublicIP:PublicIpAddress}" \
  --region us-east-1
```

Use the returned `PublicIP` for Step 5 below.

(Alternative, if you'd rather just pick any CM node regardless of which one is running the build — both are valid failover targets:)
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names cm-server-asg-64850d \
  --query "AutoScalingGroups[0].Instances[*].InstanceId" --output text \
  --region us-east-1
```
Then get its public IP:
```bash
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text \
  --region us-east-1
```

### Step 5 — THE FAILOVER: kill Jenkins on one CM node while the build is running

```bash
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<CM_NODE_PUBLIC_IP> \
  "sudo systemctl stop cloudbees-core-cm; sudo systemctl is-active cloudbees-core-cm"
```

Narrate this out loud — this is the "pull the plug" moment.

### Step 6 — Show the ALB reacting (run live)

```bash
for i in $(seq 1 40); do
  echo "$(date -u +%H:%M:%S)  HTTP $(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://cm.training.swen.aws.ps.beescloud.com/whoAmI/api/json)"
  sleep 3
done
```

Expect a few `502`s in the first ~30-90s (ALB hasn't detected the failure yet — 3 failed checks × 30s interval ≈ 90s worst case), then it settles into clean `200`s.

### Step 7 — Show target health transition (run alongside or after Step 6)

```bash
watch -n 10 'aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table \
  --region us-east-1'
```

### Step 8 — The punchline: the build finished successfully anyway

```bash
curl -sk -u admin:admin 'https://cm.training.swen.aws.ps.beescloud.com/job/failoverDemo/lastBuild/api/json?tree=result,building,duration'
```

Or refresh the browser console page — it shows `Finished: SUCCESS` even though the node that started it is dead. The actual shell execution ran on a separate agent, and job state lives on shared EFS — the controller dying didn't destroy the build.

### Step 9 — Restore full HA (bring the killed node back)

```bash
ssh -o StrictHostKeyChecking=no -i c_swen-cdro-test1-64850d.pem ec2-user@<CM_NODE_PUBLIC_IP> \
  "sudo systemctl start cloudbees-core-cm; sudo systemctl is-active cloudbees-core-cm"
```

### Step 10 — Confirm both nodes healthy again (close the loop)

```bash
sleep 100  # allow time to pass the 3x healthy-check threshold (30s interval)
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:324005994172:targetgroup/cb-cm-tg-64850d/3d2496763fba26eb" \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State}" \
  --output table \
  --region us-east-1
```

---

## Practical notes

- **Region gotcha (verified the hard way):** the `324005994172_infra-admin` profile's default region is `us-east-2`, not `us-east-1` where this environment runs. Every `aws` command in this doc includes `--region us-east-1` explicitly for this reason — don't strip it when copying commands, and set `AWS_DEFAULT_REGION=us-east-1` per the Prerequisites as a backstop.
- Always export `AWS_PROFILE=324005994172_infra-admin` before running AWS CLI commands, and run SSH commands from the repo root (or use the full path to the `.pem` file).
- Instance IDs and public IPs churn over time (ASG replacements, EIP reassignment) — never hardcode them from a prior run; re-resolve immediately before each step that needs them.
- The Rolling Upgrade demo deliberately does **not** use Terraform or the ASG's `instance_refresh` — it's a manual, CLI-driven procedure (deregister → stop → dnf install → start → verify → re-register) so you can narrate each step as a distinct action. Total time is dominated by two things: the ~60s JVM warmup after each `systemctl start`, and the ~90-100s ALB healthy-threshold wait after re-registering.
- The failover demo's 502 window (Step 6) is the dramatic moment — don't rush past it; it's proof the ALB's detection isn't instant but self-heals within the configured thresholds.
- If `jq` is available, replace the `python3 -c "import json..."` crumb-extraction with `| jq -r .crumb` for brevity.

## Known gaps surfaced during rehearsal (informational, not blocking)

- OC↔CM handshake can break if OC is hard-replaced (OC has no persistent state across replacement) — doesn't affect pipeline execution, but affects CJOC's "Manage Controllers" view.
- The `shared-agent` / `ssh-agent` labels may show offline if `agent1` was replaced and something is IP-pinned rather than DNS-based — check `https://cm.training.swen.aws.ps.beescloud.com/computer/` before relying on those labels in a live demo. The `failoverDemo` job in this doc uses `agent any` specifically to avoid this dependency.
- If you ever want to do the upgrade via Terraform/ASG `instance_refresh` instead of manually, note that `aws_instance` resources (like `oc_server`) do **not** force-replace on `user_data` changes by default — AWS accepts the update but won't re-run cloud-init on a running instance. Only `ami` changes force a true replacement. The CM fleet's `aws_launch_template` + `aws_autoscaling_group` + `instance_refresh` combo (see `main.tf`) is the only path in this module that reliably re-triggers cloud-init on version bumps.
