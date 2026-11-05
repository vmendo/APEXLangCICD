#!/usr/bin/env bash
# Download and deploy a published release without regenerating it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/aux/common.sh"
[[ $# -eq 2 || ( $# -eq 3 && "$3" == --resume ) ]] || die "Usage: $0 <PRO> <version> [--resume]"
resume=false
[[ "${3:-}" != --resume ]] || resume=true
require_tools git gh python3 shasum
load_project
attempt="$DEMO_HOME/.state/deployment-attempt.json"
if [[ "$resume" == true ]]; then
  [[ -f "$attempt" ]] || die "No interrupted deployment exists to resume."
else
  [[ ! -f "$attempt" ]] || die "A prior deployment needs inspection. After diagnosis, use: $0 PRO <version> --resume"
fi
environment="$1"
version="$2"
validate_version "$version"
[[ "$SQLCL_DEPLOY_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "SQLCL_DEPLOY_TIMEOUT must be a positive integer."
[[ "$environment" == PRO || "$environment" == pro ]] || die "Supported environment: PRO. Configure DB_CONNECT_PRO for the intended target."
if [[ "$resume" != true ]]; then
  "$SCRIPT_DIR/aux/resolve_target_appid.sh"
  load_project
else
  APEX_APP_ID_PRO="$(python3 - "$attempt" "$PROJECT_DIR" "$version" "$DEMO_HOME/.state/deployments" <<'PY'
import json,sys
from pathlib import Path
m=json.loads(Path(sys.argv[1]).read_text())
if m['project_dir']!=str(Path(sys.argv[2]).resolve()) or m['version']!=sys.argv[3]:
    raise SystemExit('Interrupted deployment belongs to another project/version.')
p=Path(m['snapshot_dir'])
if p.is_symlink() or not p.resolve(strict=True).is_relative_to(Path(sys.argv[4]).resolve(strict=True)):
    raise SystemExit('Interrupted deployment snapshot is outside the state directory.')
before=json.loads((p/'before.json').read_text())
value=before['app_id']
if isinstance(value,bool) or not isinstance(value,int) or value<=0: raise SystemExit('Invalid original target application ID.')
print(value)
PY
)" || die "Interrupted target identity validation failed."
  export APEX_APP_ID_PRO
fi
"$SCRIPT_DIR/aux/check_environment.sh" PRO
tag="${RELEASE_TAG_PREFIX:-v}${version}"
artifact_name="$PROJECT_NAME-$version.zip"
mkdir -p "$PROJECT_DIR/artifacts"
download_dir="$(mktemp -d "$PROJECT_DIR/artifacts/$version.XXXXXX")"
gh release download "$tag" --repo "$GITHUB_REPO" --pattern "$artifact_name" --pattern "$artifact_name.sha256" --dir "$download_dir"
(cd "$download_dir" && shasum -a 256 -c "$artifact_name.sha256")
artifact="$download_dir/$artifact_name"
[[ -s "$artifact" ]] || die "Downloaded release artifact is missing."
cd "$PROJECT_DIR"
[[ -z "$(git status --porcelain)" ]] || die "Project working tree must be clean."
original_ref="$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)"
git fetch origin "refs/tags/$tag:refs/tags/$tag"
git checkout --detach "$tag"
trap 'git checkout "$original_ref" >/dev/null 2>&1 || true' EXIT
if [[ "$resume" == true ]]; then
  snapshot_dir="$(python3 - "$attempt" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['snapshot_dir'])
PY
)"
  resume_inventory="$snapshot_dir/resume-$(date -u +%Y%m%dT%H%M%S)-$$.json"
  "$SCRIPT_DIR/aux/capture_target_inventory.sh" "$resume_inventory"
  python3 "$SCRIPT_DIR/aux/deployment_resume.py" --project-dir "$PROJECT_DIR" --attempt "$attempt" --inventory "$resume_inventory" --artifact "$artifact" --version "$version" --output "$resume_inventory.preflight.json"
  # Bind retries to the exact artifact downloaded by the interrupted attempt.
  python3 - "$attempt" "$artifact" "$PROJECT_DIR" "$artifact_name" <<'PY'
import hashlib,json,sys
from pathlib import Path
m=json.loads(Path(sys.argv[1]).read_text());artifact=Path(sys.argv[2])
digest=hashlib.sha256(artifact.read_bytes()).hexdigest()
expected=m.get('artifact_sha256')
if not expected:
    cached=[p for p in (Path(sys.argv[3])/'artifacts').glob('*/'+sys.argv[4]) if p.resolve()!=artifact.resolve()]
    checks={hashlib.sha256(p.read_bytes()).hexdigest() for p in cached}
    if checks!={digest}: raise SystemExit('Original cached artifact is missing, changed or ambiguous; inspect before retrying.')
elif expected!=digest: raise SystemExit('Published artifact differs from the interrupted deployment.')
print('Resume uses the identical interrupted release artifact.')
PY
  defaults="$snapshot_dir/resume-target-$(date -u +%Y%m%dT%H%M%S)-$$.properties"
  python3 "$SCRIPT_DIR/aux/prepare_deploy_defaults.py" "$artifact" "$resume_inventory" "$defaults"
  # Confirm the old client is gone before the user-requested retry releases its
  # stale lock. Any other target-schema session requires manual inspection.
  read -r verified_db verified_service < <(python3 - "$resume_inventory" <<'PY'
import json,re,sys
m=json.load(open(sys.argv[1]))
if not all(re.fullmatch(r'[A-Za-z0-9_.-]+',m[k]) for k in ('database','service')):raise SystemExit('Invalid database identity.')
print(m['database'],m['service'])
PY
)
  [[ -n "$verified_db" && -n "$verified_service" ]] || die "Could not verify resume database identity."
  echo "Checking that no production-schema sessions remain before recovering the interrupted migration..."
  run_sql "$DB_CONNECT_ADMIN" resume-deployment-sessions <<EOF
set serveroutput on
declare n number;begin
  if user<>'ADMIN' or sys_context('USERENV','DB_NAME')<>'$verified_db'
     or sys_context('USERENV','SERVICE_NAME')<>'$verified_service' then
    raise_application_error(-20090,'Resume administrative database identity mismatch');
  end if;
  select count(*) into n from v\$session where username='$SCHEMA_NAME_PRO';
  if n>0 then raise_application_error(-20091,'Production schema still has sessions; inspect them before releasing a migration lock');end if;
end;
/
EOF
  run_sql "$DB_CONNECT_PRO" resume-deployment-lock <<EOF
begin
  if user<>'$SCHEMA_NAME_PRO' or sys_context('USERENV','DB_NAME')<>'$verified_db'
     or sys_context('USERENV','SERVICE_NAME')<>'$verified_service' then
    raise_application_error(-20092,'Resume lock recovery database identity mismatch');
  end if;
end;
/
lb release-locks
EOF
else
  snapshot_dir="$DEMO_HOME/.state/deployments/$version-$(date -u +%Y%m%dT%H%M%S)-$$"
  mkdir -p "$snapshot_dir"
  "$SCRIPT_DIR/aux/capture_target_inventory.sh" "$snapshot_dir/before.json"
  python3 "$SCRIPT_DIR/aux/deployment_preflight.py" "$PROJECT_DIR" "$snapshot_dir/before.json" "$DEMO_HOME/.state/production-setup.json" "$DEMO_HOME/.state/deployment.json"
  defaults="$snapshot_dir/target.properties"
  python3 "$SCRIPT_DIR/aux/prepare_deploy_defaults.py" "$artifact" "$snapshot_dir/before.json" "$defaults"
  python3 - "$attempt" "$snapshot_dir" "$version" "$PROJECT_DIR" "$artifact" <<'PY'
import hashlib,json,os,sys
from datetime import datetime,timezone
fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:
    json.dump(dict(snapshot_dir=sys.argv[2],version=sys.argv[3],project_dir=sys.argv[4],started_utc=datetime.now(timezone.utc).isoformat(),artifact_sha256=hashlib.sha256(open(sys.argv[5],'rb').read()).hexdigest()),f,indent=2)
PY
fi
rm -f "$DEMO_HOME/.state/deployment.cleaned.json"
echo "Deploying release $version (timeout ${SQLCL_DEPLOY_TIMEOUT}s). SQLcl reports progress every 15 seconds while running."
SQLCL_TIMEOUT="$SQLCL_DEPLOY_TIMEOUT" run_sql "$DB_CONNECT_PRO" "deploy-$version" <<EOF
project deploy -file "$artifact" -defaults-file "$defaults" -verbose
EOF
"$SCRIPT_DIR/aux/check_environment.sh" PRO
after="$snapshot_dir/after-$(date -u +%Y%m%dT%H%M%S)-$$.json"
"$SCRIPT_DIR/aux/capture_target_inventory.sh" "$after"
python3 "$SCRIPT_DIR/aux/record_deployment.py" --project-dir "$PROJECT_DIR" --production-setup "$DEMO_HOME/.state/production-setup.json" --version "$version" --before "$snapshot_dir/before.json" --after "$after" --output "$DEMO_HOME/.state/deployment.json"
rm -f "$DEMO_HOME/.state/deployment-attempt.json"
printf 'Deployed and recorded %s to %s. Run target validation before continuing.\n' "$version" "$DB_CONNECT_PRO"
