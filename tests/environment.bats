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
