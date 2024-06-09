# Either + or ~, depending on the value of --incompatible_use_plus_in_repo_name.
REPO_NAME_SEPARATOR = Label("@bazel_env.bzl").workspace_name.removeprefix("bazel_env.bzl")[0]
