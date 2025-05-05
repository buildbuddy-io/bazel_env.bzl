load("@bazel_skylib//rules:write_file.bzl", "write_file")

def _rlocation_path(ctx, file):
    # type: (ctx, File) -> string
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _heuristic_rlocation_path(ctx, path):
    # type: (ctx, string) -> string
    if path.startswith("bazel-out/"):
        # Skip over bazel-out/<cfg>/bin.
        path = "/".join(path.split("/")[3:])

    if path.startswith("external/"):
        return path.removeprefix("external/")
    elif path.startswith("../"):
        return path[3:]
    elif path.startswith("/"):
        return path
    elif not path.startswith(ctx.workspace_name + "/"):
        return ctx.workspace_name + "/" + path
    else:
        return path

# Based on:
# https://github.com/bazelbuild/bazel/blob/73b0faff39ed435b3cbeb09c93185b155fbd3e09/src/main/starlark/builtins_bzl/common/cc/cc_helper.bzl#L749C1-L802C27
def _expand_make_variables(expression, vars):
    # type: (string, dict[string, string]) -> tuple[string, dict[string, bool]]
    idx = 0
    last_make_var_end = 0
    result = []
    n = len(expression)
    vars_used = {}
    for _ in range(n):
        if idx >= n:
            break
        if expression[idx] != "$":
            idx += 1
            continue

        idx += 1

        # We've met $$ pattern, so $ is escaped.
        if idx < n and expression[idx] == "$":
            idx += 1
            result.append(expression[last_make_var_end:idx - 1])
            last_make_var_end = idx
            # We might have found a potential start for Make Variable.

        elif idx < n and expression[idx] == "(":
            # Try to find the closing parentheses.
            make_var_start = idx
            make_var_end = make_var_start
            for j in range(idx + 1, n):
                if expression[j] == ")":
                    make_var_end = j
                    break

            # Note we cannot go out of string's bounds here,
            # because of this check.
            # If start of the variable is different from the end,
            # we found a make variable.
            if make_var_start != make_var_end:
                # Some clarifications:
                # *****$(MAKE_VAR_1)*******$(MAKE_VAR_2)*****
                #                   ^       ^          ^
                #                   |       |          |
                #   last_make_var_end  make_var_start make_var_end
                result.append(expression[last_make_var_end:make_var_start - 1])
                make_var = expression[make_var_start + 1:make_var_end]

                # Fail on location expansion.
                if " " in make_var:
                    fail("location expansion such as '$(rlocationpath ...)' is not supported: $({})".format(make_var))
                exp = vars.get(make_var)
                if exp == None:
                    fail("variable $({}) is not defined".format(make_var))
                vars_used[make_var] = True
                result.append(exp)

                # Update indexes.
                idx = make_var_end + 1
                last_make_var_end = idx

    # Add the last substring which would be skipped by for loop.
    if last_make_var_end < n:
        result.append(expression[last_make_var_end:n])

    return "".join(result), vars_used

_COMPILATION_MODE_SETTING = "//command_line_option:compilation_mode"
_CPU_SETTING = "//command_line_option:cpu"
_EXTRA_EXECUTION_PLATFORMS_SETTING = "//command_line_option:extra_execution_platforms"
_HOST_CPU_SETTING = "//command_line_option:host_cpu"
_HOST_PLATFORM_SETTING = "//command_line_option:host_platform"
_ALL_SETTINGS = [
    _COMPILATION_MODE_SETTING,
    _CPU_SETTING,
    _EXTRA_EXECUTION_PLATFORMS_SETTING,
    _HOST_CPU_SETTING,
    _HOST_PLATFORM_SETTING,
]

def _flip_output_dir_impl(settings, _attr):
    # type: (dict[string, string | list[string]], attr) -> dict[string, string]
    if settings[_CPU_SETTING] != "bazel_env":
        # Force "opt" mode for tools as they aren't rebuilt frequently and should be fast.
        # Force the output directory mnemonic to be the fixed string "bazel_env-opt" on all
        # platforms by using a fake CPU.
        # Also ensure that the host platform has the highest precedence among the registered
        # execution platforms so that toolchain resolution picks one that runs on the host.
        # Note: We keep the target platform as is so that users can use toolchains with
        # target constraints that are not the host platform, e.g., to have a C++ compiler compile
        # for WASM if that's what the project usually does by setting `--platforms`.
        return settings | {
            _COMPILATION_MODE_SETTING: "opt",
            _EXTRA_EXECUTION_PLATFORMS_SETTING: [settings[_HOST_PLATFORM_SETTING]],
            _CPU_SETTING: "bazel_env",
        }
    else:
        # Switch back to the host CPU for building tools and selecting toolchains. With Bazel 7,
        # they usually shouldn't care about the value of --cpu and "bazel_env" is very unlikely
        # to have a platform mapping, but it's less confusing and potentially better for caching
        # if tool artifacts are under meaningful output directories.
        return settings | {
            _CPU_SETTING: settings[_HOST_CPU_SETTING],
        }

_flip_output_dir = transition(
    implementation = _flip_output_dir_impl,
    inputs = _ALL_SETTINGS,
    outputs = _ALL_SETTINGS,
)

_ToolInfo = provider(fields = ["name", "raw_tool"])

def _tool_impl(ctx):
    # type: (ctx) -> list[Provider]
    name = ctx.label.name.rpartition("/")[-1]
    out = ctx.actions.declare_file(ctx.label.name)

    extra_env = {}
    if ctx.attr.path:
        vars = {
            k: v
            for toolchain in ctx.attr.toolchain_targets
            if platform_common.TemplateVariableInfo in toolchain
            for k, v in toolchain[platform_common.TemplateVariableInfo].variables.items()
        }
        raw_path, used_vars = _expand_make_variables(ctx.attr.path, vars)
        rlocation_path = _heuristic_rlocation_path(ctx, raw_path)

        transitive_files = []
        for toolchain in ctx.attr.toolchain_targets:
            if platform_common.TemplateVariableInfo in toolchain:
                for key in toolchain[platform_common.TemplateVariableInfo].variables.keys():
                    if key in used_vars:
                        transitive_files.append(toolchain[DefaultInfo].files)
        runfiles = ctx.runfiles(transitive_files = depset(transitive = transitive_files))
    else:
        # There is only ever a single target, the attribute only takes an array value because of the transition.
        target = ctx.attr.target[0]

        rlocation_path = _rlocation_path(ctx, ctx.executable.target)

        runfiles = ctx.runfiles(ctx.files.target)
        runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

        if RunEnvironmentInfo in target:
            extra_env = target[RunEnvironmentInfo].environment

    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = out,
        is_executable = True,
        substitutions = {
            "{{bazel_env_label}}": str(ctx.label).removeprefix("@@").removesuffix("/bin/" + name),
            "{{rlocation_path}}": rlocation_path,
            "{{extra_env}}": "\n".join([
                "export {}={}".format(k, repr(v))
                for k, v in extra_env.items()
            ]),
        },
    )

    return [
        DefaultInfo(
            executable = out,
            runfiles = runfiles,
        ),
        _ToolInfo(
            name = name,
            raw_tool = ctx.attr.raw_tool,
        ),
    ]

_tool = rule(
    implementation = _tool_impl,
    attrs = {
        "target": attr.label(
            allow_files = True,
            cfg = _flip_output_dir,
            executable = True,
        ),
        "path": attr.string(),
        "raw_tool": attr.string(),
        "toolchain_targets": attr.label_list(
            cfg = _flip_output_dir,
            allow_files = True,
        ),
        "_launcher": attr.label(
            allow_single_file = True,
            cfg = _flip_output_dir,
            default = ":launcher.sh.tpl",
            executable = True,
        ),
    },
    executable = True,
)

def _toolchain_impl(ctx):
    # type: (ctx) -> list[Provider]
    toolchain_name = ctx.label.name.rpartition("/")[-1]

    repos = {file.owner.workspace_root: None for file in ctx.files.target}
    target = ctx.attr.target[0]
    if not repos:
        suffix = ""
        if target.label.name == "toolchain_type":
            suffix = ". 'toolchain_type' targets are not supported here, look for a 'current_*_{runtime,toolchain}' target instead."
        fail(
            "toolchain target",
            target.label,
            "for '{}' has no files{}".format(toolchain_name, suffix),
        )
    if len(repos) > 1:
        fail(
            "toolchain target",
            target.label,
            "for '{}' has files from different repositories: {}".format(
                toolchain_name,
                ", ".join(repos.keys()),
            ),
        )
    single_repo = repos.keys()[0]

    # bazel_env/toolchains/jdk --> 2 segments as symlink resolution is relative to the parent of jdk
    up_to_output_base_segments = ctx.label.name.count("/")

    # pkg/foo --> 2 segments, pkg --> 1 segment, but the root package should be counted as 0 segments
    up_to_output_base_segments += ctx.label.package.count("/") + 1 if ctx.label.package else 0

    # bazel-out/k8-fastbuild/bin --> 3 segments
    up_to_output_base_segments += ctx.bin_dir.path.count("/") + 1

    # execroot/<workspace_name> --> 2 segments
    up_to_output_base_segments += 2

    out = ctx.actions.declare_symlink(ctx.label.name)
    ctx.actions.symlink(output = out, target_path = up_to_output_base_segments * "../" + single_repo)

    return [
        DefaultInfo(files = depset([out])),
    ]

_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "target": attr.label(
            cfg = _flip_output_dir,
            allow_files = True,
        ),
    },
)

def _bazel_env_rule_impl(ctx):
    # type: (ctx) -> list[Provider]
    implicit_out = ctx.actions.declare_file(ctx.label.name + "_all_tools")

    unique_name_tool = ctx.attr.unique_name_tool[DefaultInfo].files.to_list()[0]

    # It is not necessary to stage the toolchain files (which are in runfiles) as inputs as their
    # repos have already been fetched before the toolchain rules were analyzed.
    transitive_inputs = [toolchain[DefaultInfo].files for toolchain in ctx.attr.toolchain_targets]
    direct_inputs = [unique_name_tool, ctx.file.all_tools_file]
    tools = [tool[DefaultInfo].files_to_run for tool in ctx.attr.tool_targets]
    ctx.actions.run_shell(
        outputs = [implicit_out],
        inputs = depset(direct_inputs, transitive = transitive_inputs),
        tools = tools,
        command = """
        touch "$1"
        """,
        arguments = [implicit_out.path],
        # Run this action locally to force the runfiles directories for the tools to be created even
        # with --nobuild_runfile_links.
        execution_requirements = {
            "no-cache": "",
            "no-remote": "",
            "no-sandbox": "",
        },
    )

    tool_infos = [tool[_ToolInfo] for tool in ctx.attr.tool_targets]
    tool_name_pad = max([len(tool_info.name) for tool_info in tool_infos] + [0])

    toolchain_infos = [struct(
        name = toolchain.label.name.rpartition("/")[-1],
        path = toolchain[DefaultInfo].files.to_list()[0].path,
    ) for toolchain in ctx.attr.toolchain_targets]
    toolchain_name_pad = max([len(toolchain_info.name) for toolchain_info in toolchain_infos] + [0])

    status_script = ctx.actions.declare_file(ctx.label.name + ".sh")
    tool_regex = "\\|".join([tool_info.name for tool_info in tool_infos] + [unique_name_tool.basename, ctx.file.all_tools_file.basename])
    ctx.actions.expand_template(
        template = ctx.file._status,
        output = status_script,
        is_executable = True,
        substitutions = {
            "{{name}}": ctx.label.name,
            # We assume that the target is in the main repo and want the label to look like this:
            # //:bazel_env
            "{{label}}": str(ctx.label).removeprefix("@@"),
            "{{bin_dir}}": unique_name_tool.dirname,
            "{{unique_name_tool}}": unique_name_tool.basename,
            "{{has_tools}}": str(bool(tool_infos)),
            "{{tools_regex}}": tool_regex,
            "{{tools}}": "\n".join(
                [
                    "  * {}:{} {}".format(tool_info.name, (tool_name_pad - len(tool_info.name)) * " ", tool_info.raw_tool)
                    for tool_info in tool_infos
                ],
            ),
            "{{has_toolchains}}": str(bool(ctx.attr.toolchain_targets)),
            "{{toolchains}}": "\n".join(
                [
                    "  * {}:{} {}".format(toolchain_info.name, (toolchain_name_pad - len(toolchain_info.name)) * " ", toolchain_info.path)
                    for toolchain_info in toolchain_infos
                ],
            ),
        },
    )

    return [
        DefaultInfo(
            executable = status_script,
            files = depset([implicit_out]),
        ),
    ]

_bazel_env_rule = rule(
    cfg = _flip_output_dir,
    implementation = _bazel_env_rule_impl,
    attrs = {
        "all_tools_file": attr.label(allow_single_file = True),
        "unique_name_tool": attr.label(),
        "tool_targets": attr.label_list(
            providers = [_ToolInfo],
        ),
        "toolchain_targets": attr.label_list(),
        "_status": attr.label(
            allow_single_file = True,
            cfg = "target",
            default = ":status.sh.tpl",
            executable = True,
        ),
    },
    executable = True,
)

_FORBIDDEN_TOOL_NAMES = ["direnv", "bazel", "bazelisk"]

def bazel_env(*, name, tools = {}, toolchains = {}, **kwargs):
    # type: (string, dict[string, string | Label], dict[string, string | Label]) -> None
    """Makes Bazel-managed tools and toolchains available under stable paths.

    Build this target to make the given tools and toolchains available under stable,
    platform-independent paths:

    * tools are staged in `bazel-out/bazel_env-opt/bin/path/to/pkg/name/bin`
    * toolchains are staged in `bazel-out/bazel_env-opt/bin/path/to/pkg/name/toolchains`

    Run this target with `bazel run` for instructions on how to make the tools available on `PATH`
    using [`direnv`](https://direnv.net/). This also prints a list of all tools and toolchains as
    well as cleans up stale tools.

    Args:
        name: The name of the rule.

        tools: A dictionary mapping tool names to their targets or paths. The name is used as the
            basename of the tool in the `bin` directory and will be available on `PATH`.

            If a target is provided, the corresponding executable is staged in the `bin` directory
            together with its runfiles.

            If a path is provided, Make variables provided by `toolchains` are expanded in it and
            all the files of referenced toolchains are staged as runfiles.

        toolchains: A dictionary mapping toolchain names to their targets. The name is used as the
            basename of the toolchain directory in the `toolchains` directory. The directory is
            a symlink to the repository root of the (single) repository containing the toolchain.

        **kwargs: Additional arguments to pass to the main `bazel_env` target. It is usually not
            necessary to provide any and the target should have private visibility.
    """
    tool_targets = []
    toolchain_targets = []

    reversed_toolchains = {
        toolchain: toolchain_name
        for toolchain_name, toolchain in toolchains.items()
    }

    # This name is supposed to be unique in PATH on a best-effort basis. If it isn't unique,
    # status.sh may fail to detect that direnv isn't set up correctly - it looks for this tool
    # in PATH to determine if the environment is active.
    unique_suffix = "_bazel_env_marker_{}_{}_{}_{}".format(
        native.module_name(),
        native.module_version(),
        native.package_name(),
        name,
    ).replace("/", "-")
    unique_name_tool = name + "/bin/" + unique_suffix
    write_file(
        name = unique_name_tool,
        out = unique_name_tool + ".sh",
        content = ["#!/usr/bin/env bash", "exit 0"],
        is_executable = True,
        visibility = ["//visibility:private"],
        tags = ["manual"],
    )
    all_tools_file = name + "/bin/_all_tools"
    write_file(
        name = all_tools_file,
        out = all_tools_file + ".txt",
        # List all tools in a format that is easy to grep.
        content = [" " + " ".join(tools.keys()) + " "],
        is_executable = False,
        visibility = ["//visibility:private"],
        tags = ["manual"],
    )

    for tool_name, tool in tools.items():
        if not tool_name:
            fail("empty tool names are not allowed")
        if tool_name in _FORBIDDEN_TOOL_NAMES:
            fail("tool name '{}' is forbidden".format(tool_name))
        tool_kwargs = {}
        is_str = type(tool) == type("")
        if is_str and "$" in tool:
            tool_kwargs["path"] = tool
        elif is_str and tool.startswith("/") and not tool.startswith("//"):
            fail("absolute paths are not supported, got '{}' for tool '{}'".format(tool, tool_name))
        else:
            tool_kwargs["target"] = tool

        tool_target_name = name + "/bin/" + tool_name
        tool_targets.append(tool_target_name)
        _tool(
            name = tool_target_name,
            raw_tool = str(tool),
            toolchain_targets = reversed_toolchains,
            visibility = ["//visibility:private"],
            tags = ["manual"],
            **tool_kwargs
        )

    for toolchain_name, toolchain in toolchains.items():
        if not toolchain_name:
            fail("empty toolchain names are not allowed")
        toolchain_target_name = name + "/toolchains/" + toolchain_name
        toolchain_targets.append(toolchain_target_name)
        _toolchain(
            name = toolchain_target_name,
            target = toolchain,
            visibility = ["//visibility:private"],
            tags = ["manual"],
        )

    _bazel_env_rule(
        name = name,
        all_tools_file = all_tools_file,
        unique_name_tool = unique_name_tool,
        tool_targets = tool_targets,
        toolchain_targets = toolchain_targets,
        **kwargs
    )
