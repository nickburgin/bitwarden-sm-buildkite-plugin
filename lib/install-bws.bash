#!/usr/bin/env bash
#
# Put the Bitwarden Secrets Manager CLI on the agent and print its path.
#
# The binary caches under BWS_CACHE_DIR by version, so only the first build on
# an agent pays the download. The musl build is static, so it runs on both a
# glibc host and an Alpine agent image.

# Print the path of the bws binary, downloading it when the cache misses.
install_bws() {
  local version="${BWS_VERSION:-2.1.0}"
  local cache_dir="${BWS_CACHE_DIR:-${HOME}/.cache/bitwarden-sm}"
  local target_dir="${cache_dir}/bws-${version}"
  local binary="${target_dir}/bws"

  if [[ -x "${binary}" ]]; then
    echo "${binary}"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *)
      echo "+++ :warning: Unsupported architecture: $(uname -m)" >&2
      return 1
      ;;
  esac

  local url="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${version}/bws-${arch}-unknown-linux-musl-${version}.zip"
  local archive="${target_dir}.zip"

  mkdir -p "${cache_dir}"
  echo "Downloading bws ${version} for ${arch}" >&2

  if ! curl -fsSL --retry 3 -o "${archive}" "${url}"; then
    echo "+++ :warning: Failed to download bws from ${url}" >&2
    rm -f "${archive}"
    return 1
  fi

  if ! unzip -o -q -d "${target_dir}" "${archive}" bws; then
    echo "+++ :warning: Failed to extract bws from ${archive}" >&2
    rm -f "${archive}"
    return 1
  fi

  rm -f "${archive}"
  chmod +x "${binary}"
  echo "${binary}"
}
