#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  export BWS_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  export BWS_VERSION=2.1.0
}

@test "downloads bws and reports the cached path" {
  stub curl \
    "-fsSL --retry 3 -o * * : touch \"\$3\"; echo downloaded"
  stub unzip \
    "-o -q -d * * bws : mkdir -p \$4 && printf '#!/bin/sh\necho stub-bws\n' > \$4/bws && chmod +x \$4/bws"

  run bash -c "source $PWD/lib/install-bws.bash && install_bws"

  assert_success
  assert_output --partial "${BWS_CACHE_DIR}/bws-2.1.0/bws"

  unstub curl
  unstub unzip
}

@test "reuses a cached binary without downloading" {
  mkdir -p "${BWS_CACHE_DIR}/bws-2.1.0"
  printf '#!/bin/sh\necho cached\n' > "${BWS_CACHE_DIR}/bws-2.1.0/bws"
  chmod +x "${BWS_CACHE_DIR}/bws-2.1.0/bws"

  # No curl stub. A download attempt fails the test with command not found.
  run bash -c "source $PWD/lib/install-bws.bash && install_bws"

  assert_success
  assert_output --partial "${BWS_CACHE_DIR}/bws-2.1.0/bws"
}

@test "fails when the download fails" {
  stub curl "-fsSL --retry 3 -o * * : exit 22"

  run bash -c "source $PWD/lib/install-bws.bash && install_bws"

  assert_failure
  assert_output --partial "Failed to download bws"

  unstub curl
}
