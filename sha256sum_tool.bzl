"""Helper resolving the sha256sum toolchain used by tool launchers."""

visibility("private")

_SHA256SUM_TOOLCHAIN_TYPE = Label("@rules_coreutils//coreutils/toolchain/sha256sum:type")

Sha256sumInfo = provider(fields = ["executable", "default_runfiles"])

def _sha256sum_tool_impl(ctx):
    # type: (ctx) -> list[Provider]
    sha256sum = ctx.toolchains[_SHA256SUM_TOOLCHAIN_TYPE]
    return [Sha256sumInfo(
        executable = sha256sum.run.executable,
        default_runfiles = sha256sum.default.default_runfiles,
    )]

sha256sum_tool = rule(
    implementation = _sha256sum_tool_impl,
    toolchains = [_SHA256SUM_TOOLCHAIN_TYPE],
)
