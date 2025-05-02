<!-- Generated with Stardoc: http://skydoc.bazel.build -->



<a id="bazel_env"></a>

## bazel_env

<pre>
load("@bazel_env.bzl", "bazel_env")

bazel_env(*, <a href="#bazel_env-name">name</a>, <a href="#bazel_env-tools">tools</a>, <a href="#bazel_env-toolchains">toolchains</a>, <a href="#bazel_env-kwargs">**kwargs</a>)
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
| <a id="bazel_env-toolchains"></a>toolchains |  A dictionary mapping toolchain names to their targets. The name is used as the basename of the toolchain directory in the `toolchains` directory. The directory is a symlink to the repository root of the (single) repository containing the toolchain.   |  `{}` |
| <a id="bazel_env-kwargs"></a>kwargs |  Additional arguments to pass to the main `bazel_env` target. It is usually not necessary to provide any and the target should have private visibility.   |  none |


