# bazel_env.bzl

The `bazel_env` rule creates a "virtual environment" for Bazel-managed tools and toolchains by making them available under stable, platform-independent paths as well as on `PATH`.
This allows all developers to share the same tool versions as used in the Bazel build for IDEs and local usage.

`bazel_env` relies on the [`direnv`](https://direnv.net/) tool to automatically set up `PATH` when entering the project directory.
When you run the `bazel_env` target, it will print instructions on how to set up `direnv` and its `.envrc` file.

🎙️ This rule was featured on the Aspect Insights podcast:

[![Developer Tooling in Monorepos with bazel_env ](https://img.youtube.com/vi/TDyUvaXaZrc/0.jpg)](https://www.youtube.com/watch?v=TDyUvaXaZrc&list=PLLU28e_DRwdtpojOqWM5UeFyxad7m9gCF&index=1)

## Example

The [example](examples/) includes some commonly used tools and toolchains.

## Setup

### Once per project

1. Add a dependency on `bazel_env.bzl` to your `MODULE.bazel` file:

```starlark
bazel_dep(name = "bazel_env.bzl", version = "<latest release>", dev_dependency = True)
```

2. Add a `bazel_env` target to a `BUILD.bazel` file (e.g. top-level or in a `tools` directory):

```starlark
load("@bazel_env.bzl", "bazel_env")

bazel_env(
    name = "bazel_env",
    toolchains = {
        "jdk": "@rules_java//toolchains:current_host_java_runtime",
    },
    tools = {
        # Tools can be specified as labels.
        "buildifier": "@buildifier_prebuilt//:buildifier",
        "go": "@rules_go//go",
        # Tool paths can also reference the Make variables provided by toolchains.
        "jar": "$(JAVABASE)/bin/jar",
        "java": "$(JAVA)",
    },
)
```

3. Run the `bazel_env` target and follow the instructions to install `direnv` and set up the `.envrc` file, which should be committed to version control:

```
$ bazel run //:bazel_env
====== bazel_env ======

✅ direnv is installed
❌ bazel_env's bin directory is not in PATH. Please follow these steps:

1. Enable direnv's shell hook as described in https://direnv.net/docs/hook.html.

2. Add the following snippet to a .envrc file next to your MODULE.bazel file:

watch_file bazel-out/bazel_env-opt/bin/bazel_env/bin
PATH_add bazel-out/bazel_env-opt/bin/bazel_env/bin
if [[ ! -d bazel-out/bazel_env-opt/bin/bazel_env/bin ]]; then
  log_error "ERROR[bazel_env.bzl]: Run 'bazel run //:bazel_env' to regenerate bazel-out/bazel_env-opt/bin/bazel_env/bin"
fi

3. Allowlist the file with 'direnv allow .envrc'.
```

Multiple `bazel_env` targets can be added per project.
Note that each target will eagerly fetch and build all tools and toolchains when built, so consider splitting them up into workflow-specific targets if necessary.

### Once per user

1. Run the `bazel_env` target and follow the instructions to install `direnv` and allowlist the `.envrc` file:

```
$ bazel run //:bazel_env
====== bazel_env ======

✅ direnv is installed
❌ bazel_env's bin directory is not in PATH. Please follow these steps:

1. Enable direnv's shell hook as described in https://direnv.net/docs/hook.html.

2. Add the following snippet to a .envrc file next to your MODULE.bazel file:

watch_file bazel-out/bazel_env-opt/bin/bazel_env/bin
PATH_add bazel-out/bazel_env-opt/bin/bazel_env/bin
if [[ ! -d bazel-out/bazel_env-opt/bin/bazel_env/bin ]]; then
  log_error "ERROR[bazel_env.bzl]: Run 'bazel run //:bazel_env' to regenerate bazel-out/bazel_env-opt/bin/bazel_env/bin"
fi

3. Allowlist the file with 'direnv allow .envrc'.
```

2. Run the target again to get a list of all tools and toolchains:

```
====== bazel_env ======

✅ direnv is installed
✅ direnv added bazel-out/bazel_env-opt/bin/bazel_env/bin to PATH

Tools available in PATH:
  * buildifier: @buildifier_prebuilt//:buildifier
  * go:         @rules_go//go
  * jar:        $(JAVABASE)/bin/jar
  * java:       $(JAVA)

Toolchains available at stable relative paths:
  * jdk: bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk
```

### Without `direnv` (e.g., in CI)

Run the `print-path` subcommand of the `bazel_env` target and manually add its output to your `PATH`.
For GitHub Actions, this can be done as follows:

```
$ bazel run //:bazel_env print-path >> $GITHUB_PATH
```

### Fetching external tools

[`rules_multitool`](https://github.com/theoremlp/rules_multitool) makes it easy to fetch tool binaries that match the host machine's architecture and OS and conveniently integrates with your `bazel_env` targets.
If you define a multitool hub called `multitool`, just `load` the `TOOLS` dict from `@multitool//:tools.bzl` and append it to the `tools` attribute of your `bazel_env` target via `|`.
The [example](examples/) demonstrates a use of `rules_multitool` to fetch tools such as `docker-compose` and `terraform`.

## Usage

Build the `bazel_env` target to keep the tools and toolchains up-to-date with the Bazel build.
The target can also be executed with `bazel run` to print the list of tools and toolchains as well as clean up removed tools.

> [!IMPORTANT]
> Shells such as `bash` and `zsh` will not automatically pick up changes to directories in `PATH`.
> You may need to run `hash -r` or `rehash` to clear the shell's command cache.
> `bazel run //:bazel_env` will print the command to run.

You can reduce the verbosity of what direnv prints when you enter a folder, by adjusting the `log_filter` option in `~/.config/direnv/direnv.toml`.
See https://github.com/direnv/direnv/issues/68#issuecomment-2812015043.

## Documentation

See the [generated documentation](docs-gen/bazel_env.md) for more information on the `bazel_env` rule.
