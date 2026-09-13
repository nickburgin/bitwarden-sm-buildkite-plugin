#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  export BUILDKITE_PIPELINE_SLUG=my-app
  export BWS_ACCESS_TOKEN=fake-token
  export BUILDKITE_PLUGIN_BITWARDEN_SM_PROJECT_ID=proj-1234
  export BUILDKITE_PLUGIN_BITWARDEN_SM_DUMP_ENV=true
}

teardown() {
  unset BUILDKITE_STEP_KEY
}

# A bws secret list response holding the given key/value pairs.
secret_list_json() {
  local out='['
  local first=1
  while (( $# > 0 )); do
    [[ $first -eq 1 ]] || out+=','
    first=0
    out+="{\"id\":\"id-$1\",\"key\":\"$1\",\"value\":\"$2\",\"note\":\"\"}"
    shift 2
  done
  echo "${out}]"
}

#-------
# Pipeline scope

@test "exports a pipeline-scoped secret with the prefix removed" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__GIT_TOKEN abc123)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "GIT_TOKEN=abc123"

  unstub bws
}

@test "ignores a secret belonging to another pipeline" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json OTHER_APP__GIT_TOKEN nope)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "GIT_TOKEN=nope"

  unstub bws
}

@test "matches a pipeline slug containing a dash" {
  export BUILDKITE_PIPELINE_SLUG=my-app

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__TOKEN yes)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "TOKEN=yes"

  unstub bws
}

#-------
# Step scope

@test "exports a step-scoped secret when the step key matches" {
  export BUILDKITE_STEP_KEY=deploy

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__DEPLOY__REGISTRY_PASSWORD hunter2)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "REGISTRY_PASSWORD=hunter2"

  unstub bws
}

@test "ignores a step-scoped secret when the step key differs" {
  export BUILDKITE_STEP_KEY=test

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__DEPLOY__REGISTRY_PASSWORD hunter2)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "REGISTRY_PASSWORD=hunter2"

  unstub bws
}

@test "ignores a step-scoped secret when the step has no key" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__DEPLOY__REGISTRY_PASSWORD hunter2)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "REGISTRY_PASSWORD=hunter2"

  unstub bws
}

@test "a step-scoped secret overrides a pipeline-scoped secret of the same name" {
  export BUILDKITE_STEP_KEY=deploy

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__TOKEN pipeline-value MY_APP__DEPLOY__TOKEN step-value)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "TOKEN=step-value"
  refute_output --partial "TOKEN=pipeline-value"

  unstub bws
}

#-------
# Values that break naive parsing

@test "keeps a value containing an equals sign and spaces intact" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__CONN "host=db user=bob pass=a b")'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "CONN=host=db user=bob pass=a b"

  unstub bws
}

@test "keeps a value containing a dollar sign and backticks literal" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__RAW "\$(whoami)")'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial 'RAW=$(whoami)'

  unstub bws
}

#-------
# Multi-line values

@test "keeps a multi-line value whole" {
  local key='-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQOYBGSECRET1\nlQOYBGSECRET2\n-----END PGP PRIVATE KEY BLOCK-----'

  stub bws \
    "secret list proj-1234 --output json : printf '%s\n' '[{\"id\":\"i\",\"key\":\"MY_APP__GPG_KEY\",\"value\":\"${key}\",\"note\":\"\"}]'"

  # Source the hook, so the exported value is readable afterwards. A subshell
  # would discard it.
  export BUILDKITE_PLUGIN_BITWARDEN_SM_DUMP_ENV=false
  run bash -c ". $PWD/hooks/environment >/dev/null && printf 'lines=%s first=%s last=%s' \
    \"\$(printf '%s' \"\${GPG_KEY}\" | wc -l)\" \
    \"\$(printf '%s' \"\${GPG_KEY}\" | head -1)\" \
    \"\$(printf '%s' \"\${GPG_KEY}\" | tail -1)\""

  assert_success
  # Three newlines means four lines, so the value survived whole.
  assert_output --partial "lines=3"
  assert_output --partial "first=-----BEGIN PGP PRIVATE KEY BLOCK-----"
  assert_output --partial "last=-----END PGP PRIVATE KEY BLOCK-----"

  unstub bws
}

@test "never prints a line of a multi-line secret value" {
  local key='-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQOYBGSECRET1\nlQOYBGSECRET2\n-----END PGP PRIVATE KEY BLOCK-----'

  stub bws \
    "secret list proj-1234 --output json : printf '%s\n' '[{\"id\":\"i\",\"key\":\"MY_APP__GPG_KEY\",\"value\":\"${key}\",\"note\":\"\"}]'"

  # dump-env is off by default in this test, so no value may reach the log.
  export BUILDKITE_PLUGIN_BITWARDEN_SM_DUMP_ENV=false

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "lQOYBGSECRET1"
  refute_output --partial "lQOYBGSECRET2"
  refute_output --partial "PGP PRIVATE KEY BLOCK"
  assert_output --partial "Exported GPG_KEY"

  unstub bws
}

@test "leaves no temporary file holding the secrets" {
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__TOKEN s3cr3t-value)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  # The hook writes the secrets to a temporary file, so nothing may remain.
  run bash -c "grep -rl s3cr3t-value '${TMPDIR}' 2>/dev/null | wc -l"
  assert_output "0"

  unstub bws
}

@test "never prints secret material in a skip message" {
  # An invalid name must not carry any of the value into the log.
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__9BAD s3cr3t-value)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "s3cr3t-value"

  unstub bws
}

#-------
# Redaction

@test "adds every exported name to BUILDKITE_REDACTED_VARS" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__DEPLOY_URL https://example.com)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  assert_output --partial "BUILDKITE_REDACTED_VARS"
  assert_output --partial "DEPLOY_URL"

  unstub bws
}

#-------
# Guards

@test "fails when BWS_ACCESS_TOKEN is not set" {
  unset BWS_ACCESS_TOKEN

  run bash -c "$PWD/hooks/environment"

  assert_failure
  assert_output --partial "BWS_ACCESS_TOKEN"
}

@test "fails when the project id is not configured" {
  unset BUILDKITE_PLUGIN_BITWARDEN_SM_PROJECT_ID

  run bash -c "$PWD/hooks/environment"

  assert_failure
  assert_output --partial "project-id"
}

@test "fails when bws returns an error" {
  stub bws \
    "secret list proj-1234 --output json : echo 'auth failed' >&2; exit 1"

  run bash -c "$PWD/hooks/environment"

  assert_failure
  assert_output --partial "Failed to list secrets"

  unstub bws
}

@test "skips a secret whose name is not a valid variable name" {
  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__9BAD nope)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "9BAD=nope"

  unstub bws
}

@test "finds its own lib when the agent sources it from a wrapper elsewhere" {
  # The agent does not execute a hook. It writes a wrapper in a temporary
  # directory and sources the hook from there, so $0 is the wrapper and only
  # BASH_SOURCE[0] holds the real plugin path.
  local wrapper_dir="${BATS_TEST_TMPDIR}/buildkite-agent-hook-wrapper"
  mkdir -p "${wrapper_dir}"
  cat > "${wrapper_dir}/wrapper" <<WRAPPER
#!/bin/bash
. "$PWD/hooks/environment"
WRAPPER
  chmod +x "${wrapper_dir}/wrapper"

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__SOURCED yes)'"

  run "${wrapper_dir}/wrapper"

  assert_success
  refute_output --partial "No such file or directory"
  assert_output --partial "SOURCED=yes"

  unstub bws
}

@test "does not leak its shell options into the agent shell" {
  # The agent sources the hook into a shell that does not use -e or -u, and
  # keeps using that shell for later hooks and the command. Leaking -u kills
  # the job at the next read of an unset variable.
  local wrapper_dir="${BATS_TEST_TMPDIR}/wrapper"
  mkdir -p "${wrapper_dir}"
  cat > "${wrapper_dir}/wrapper" <<WRAPPER
#!/bin/bash
. "$PWD/hooks/environment" >/dev/null 2>&1
echo "opts=\$-"
echo "unset var reads as [\${SOME_UNSET_VAR}]"
echo "exported A=[\${A:-MISSING}]"
echo "normalise leaked: \$(type -t __bitwarden_sm_normalise || echo no)"
echo "install_bws leaked: \$(type -t install_bws || echo no)"
echo "the agent shell survived"
WRAPPER
  chmod +x "${wrapper_dir}/wrapper"

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__A 1)'"

  run "${wrapper_dir}/wrapper"

  assert_success
  assert_output --partial "the agent shell survived"
  refute_output --partial "unbound variable"
  # The exports are the point of the hook, so they must outlive the function.
  assert_output --partial "exported A=[1]"
  assert_output --partial "normalise leaked: no"
  assert_output --partial "install_bws leaked: no"

  unstub bws
}

@test "fails the job when a guard fails and the agent sources it" {
  unset BWS_ACCESS_TOKEN

  local wrapper_dir="${BATS_TEST_TMPDIR}/wrapper"
  mkdir -p "${wrapper_dir}"
  cat > "${wrapper_dir}/wrapper" <<WRAPPER
#!/bin/bash
. "$PWD/hooks/environment"
echo "the wrapper kept going"
WRAPPER
  chmod +x "${wrapper_dir}/wrapper"

  run "${wrapper_dir}/wrapper"

  assert_failure
  assert_output --partial "BWS_ACCESS_TOKEN"
  refute_output --partial "the wrapper kept going"
}

@test "installs bws when it is not on PATH" {
  export BWS_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  mkdir -p "${BWS_CACHE_DIR}/bws-2.1.0"
  cat > "${BWS_CACHE_DIR}/bws-2.1.0/bws" <<'STUB'
#!/bin/sh
echo '[{"id":"i","key":"MY_APP__CACHED","value":"from-cache","note":""}]'
STUB
  chmod +x "${BWS_CACHE_DIR}/bws-2.1.0/bws"

  run bash -c "PATH=/usr/bin:/bin $PWD/hooks/environment"

  assert_success
  assert_output --partial "CACHED=from-cache"
}

@test "does not print a secret value when dump-env is off" {
  export BUILDKITE_PLUGIN_BITWARDEN_SM_DUMP_ENV=false

  stub bws \
    "secret list proj-1234 --output json : echo '$(secret_list_json MY_APP__GIT_TOKEN abc123)'"

  run bash -c "$PWD/hooks/environment"

  assert_success
  refute_output --partial "abc123"
  assert_output --partial "GIT_TOKEN"

  unstub bws
}
