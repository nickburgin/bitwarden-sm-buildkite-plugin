# Bitwarden Secrets Manager Buildkite Plugin

Export secrets from a [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/)
project as environment variables, scoped to the pipeline and the step that asks
for them.

## Example

```yaml
steps:
  - label: "Deploy"
    key: deploy
    command: ./deploy.sh
    plugins:
      - nickburgin/bitwarden-sm#v1.0.0:
          project-id: "8f14e45f-ceea-467a-9c71-1d61d2a3b4c5"
```

The step above gets every secret named `MY_APP__*` and `MY_APP__DEPLOY__*`, for
a pipeline with the slug `my-app`.

## Secret names

Bitwarden Secrets Manager holds a flat set of key/value pairs in one project, so
the scope lives in the key name. Two forms exist, and `__` separates each part:

| Secret key | Who gets it |
| --- | --- |
| `<PIPELINE>__<VAR>` | every step of that pipeline |
| `<PIPELINE>__<STEP_KEY>__<VAR>` | only the step with that key |

A pipeline slug and a step key change to upper case, and each dash becomes an
underscore. So the pipeline `my-app` matches the prefix `MY_APP__`, and the step
`key: deploy` matches `MY_APP__DEPLOY__`.

The plugin exports the part after the last `__`. A secret named
`MY_APP__DEPLOY__REGISTRY_PASSWORD` becomes `$REGISTRY_PASSWORD`.

A step secret overrides a pipeline secret of the same name. A step without a
`key:` gets only the pipeline secrets.

### Example project

| Secret key | Value reaches |
| --- | --- |
| `MY_APP__GIT_TOKEN` | every step of `my-app` |
| `MY_APP__DEPLOY__REGISTRY_PASSWORD` | the `deploy` step of `my-app` |
| `MY_APP__RELEASE__NPM_TOKEN` | the `release` step of `my-app` |
| `OTHER_APP__GIT_TOKEN` | no step of `my-app` |

## Authentication

The plugin reads `BWS_ACCESS_TOKEN` from the agent environment. Set it in the
agent [environment hook](https://buildkite.com/docs/agent/v3/hooks), never in a
pipeline, so no pipeline author can read it.

```bash
# /buildkite/hooks/environment on the agent
export BWS_ACCESS_TOKEN="0.abc123..."
```

Give the machine account read access to one project only.

## Configuration

### `project-id` (required, string)

The Bitwarden Secrets Manager project that holds the secrets.

### `bws-version` (optional, string)

The version of the `bws` CLI to download. Default: `2.1.0`.

### `dump-env` (optional, boolean)

Print each exported name and value. Default: `false`. Turn it on for debugging
only, because the values reach the build log.

## The bws CLI

The plugin downloads the `bws` CLI on the first build and caches it under
`~/.cache/bitwarden-sm/bws-<version>/`. Later builds reuse the cached binary.
The agent image needs no change.

Set `BWS_CACHE_DIR` to move the cache.

## Log redaction

The agent redacts a value by variable name, and the built-in patterns cover only
names such as `*_TOKEN` and `*_PASSWORD`. The plugin adds every name it exports
to `BUILDKITE_REDACTED_VARS`, so a secret named `DEPLOY_URL` is redacted too.

## Requirements

`bash`, `curl`, `jq`, and `unzip` on the agent. The stock `buildkite/agent:3`
image has all four.

## Developing

```bash
./auto/test    # run the bats tests
./auto/lint    # run the plugin linter and shellcheck
```

## License

MIT
