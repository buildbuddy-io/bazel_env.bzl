<!-- Generated with Stardoc: http://skydoc.bazel.build -->



<a id="bazel_env"></a>

## bazel_env

<pre>
load("@bazel_env.bzl", "bazel_env")

bazel_env(*, <a href="#bazel_env-name">name</a>, <a href="#bazel_env-tools">tools</a>, <a href="#bazel_env-toolchains">toolchains</a>, <a href="#bazel_env-watch_dirs">watch_dirs</a>, <a href="#bazel_env-watch_files">watch_files</a>, <a href="#bazel_env-kwargs">**kwargs</a>)
</pre>

Makes Bazel-managed tools and toolchains available under stable paths.

Build this target to make the given tools and toolchains available under stable,
platform-independent paths:

* tools are staged in `bazel-out/bazel_env-opt/bin/path/to/pkg/name/bin`
* toolchains are staged in `bazel-out/bazel_env-opt/bin/path/to/pkg/name/toolchains`

Run this target with `bazel run` for instructions on how to make the tools available on `PATH`
using [`direnv`](https://direnv.net/). This also prints a list of all tools and toolchains as
well as cleans up stale tools.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="bazel_env-name"></a>name |  The name of the rule.   |  none |
| <a id="bazel_env-tools"></a>tools |  A dictionary mapping tool names to their targets or paths. The name is used as the basename of the tool in the `bin` directory and will be available on `PATH`.<br><br>If a target is provided, the corresponding executable is staged in the `bin` directory together with its runfiles.<br><br>If a path is provided, Make variables provided by `toolchains` are expanded in it and all the files of referenced toolchains are staged as runfiles.   |  `{}` |
| <a id="bazel_env-toolchains"></a>toolchains |  A dictionary mapping toolchain names to their targets. The name is used as the basename of the toolchain directory in the `toolchains` directory. The directory is a symlink to the repository root of the (single) repository containing the toolchain.<br><br>With Bazel 9.0.0-pre.20250311.1 and later, toolchain_type targets can be used directly. In older versions, use a "resolved" toolchain target such as `@bazel_tools//tools/cpp:current_cc_toolchain` instead.   |  `{}` |
| <a id="bazel_env-watch_dirs"></a>watch_dirs |  A dictionary mapping tool names to directories that will be monitored by `bazel_env`. When any file within these directories changes, it triggers a rebuild of `bazel_env`. Paths are relative to the workspace root.<br><br>Use the tool name "_common" for directories which are common to all tools.<br><br>This attribute is fully optional. It allows you to provide a heuristic set of directories that approximates what Bazel tracks during the analysis phase. This can significantly improve performance, at the cost of manually maintaining the directory list.<br><br>When changes are detected, a message will be displayed listing the changed files (marked as "modified" or "new") before the rebuild begins.   |  `{}` |
| <a id="bazel_env-watch_files"></a>watch_files |  A dictionary mapping tool names to specific files that will be monitored by `bazel_env`. When any of these files are modified, `bazel_env` will be rebuilt. Paths are relative to the workspace root.<br><br>Use the tool name "_common" for files which are common to all tools.<br><br>Like `watch_dirs`, this attribute is optional. It gives you fine-grained control over rebuild triggers by specifying individual files rather than entire directories. This is useful when only a small set of known files affect the tool's behavior, providing even lower overhead while still mimicking Bazel's file-tracking during the analysis phase.<br><br>When changes are detected, a message will be displayed listing the changed files (marked as "modified" or "new") before the rebuild begins.<br><br>Prefer to use this over the `watch_dirs` attribute for better performance.   |  `{}` |
| <a id="bazel_env-kwargs"></a>kwargs |  Additional arguments to pass to the main `bazel_env` target. It is usually not necessary to provide any and the target should have private visibility.   |  none |


