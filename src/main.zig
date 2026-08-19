const std = @import("std");
const kz = @import("root.zig");

pub const version = "0.1.0-dev";
// SAFETY: main assigns process_io from Init before any command can call write.
var process_io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    process_io = init.io;
    var iterator = init.minimal.args.iterate();
    defer iterator.deinit();
    var argument_buffer: [32][]const u8 = undefined;
    var argument_count: usize = 0;
    while (iterator.next()) |argument| {
        if (argument_count == argument_buffer.len) return error.TooManyArguments;
        argument_buffer[argument_count] = argument;
        argument_count += 1;
    }
    const args = argument_buffer[0..argument_count];

    if (args.len < 2 or isHelp(args[1])) return printHelp();

    const command = args[1];
    if (std.mem.eql(u8, command, "version")) {
        return write("kz " ++ version ++ "\n");
    }
    if (std.mem.eql(u8, command, "doctor")) return doctor(args[2..], init.environ_map.*);
    if (std.mem.eql(u8, command, "detect")) return detect(args[2..]);
    if (std.mem.eql(u8, command, "policy")) return policyExample(args[2..]);

    try write("error: unknown command\n\n");
    try printHelp();
    return error.InvalidCommand;
}

fn isHelp(argument: []const u8) bool {
    return std.mem.eql(u8, argument, "help") or std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h");
}

fn printHelp() !void {
    try write(
        \\kz - bounded Kubernetes reliability controller
        \\
        \\Usage:
        \\  kz version
        \\  kz doctor [--json]
        \\  kz detect <healthy|oom|crashloop|image-pull|pending|service> [--json]
        \\  kz policy [--auto-risk N] [--json]
        \\
        \\The current development slice is read-only. Live Kubernetes mutation is
        \\not compiled into this CLI surface; tests exercise the policy boundary.
        \\
    );
}

fn doctor(args: []const []const u8, environ: std.process.Environ.Map) !void {
    const json = hasFlag(args, "--json");
    const token = environ.get("KUBERNETES_SERVICE_HOST") != null;
    const kubeconfig = environ.get("KUBECONFIG") != null;
    const model_url = environ.get("KZ_MODEL_BASE_URL") != null;
    const provider_name = environ.get("KZ_MODEL_PROVIDER") orelse "disabled";
    const model_name = environ.get("KZ_MODEL") orelse "not configured";

    if (json) {
        var buffer: [768]u8 = undefined;
        const output = try std.fmt.bufPrint(
            &buffer,
            "{{\"schema_version\":\"kz/v1\",\"kind\":\"Doctor\",\"read_only\":true,\"in_cluster_environment\":{s},\"kubeconfig_configured\":{s},\"model_configured\":{s},\"status\":\"development-foundation\"}}\n",
            .{ boolean(token), boolean(kubeconfig), boolean(model_url) },
        );
        return write(output);
    }
    try write("kz doctor\n");
    try write("  mode: read-only\n");
    try write(if (token) "  in-cluster environment: present\n" else "  in-cluster environment: absent\n");
    try write(if (kubeconfig) "  KUBECONFIG: configured\n" else "  KUBECONFIG: default discovery\n");
    try write(if (model_url) "  model endpoint: configured\n" else "  model endpoint: disabled\n");
    var buffer: [512]u8 = undefined;
    const model_output = try std.fmt.bufPrint(&buffer, "  model provider: {s}\n  model: {s}\n", .{ provider_name, model_name });
    try write(model_output);
}

fn detect(args: []const []const u8) !void {
    if (args.len == 0) return error.MissingScenario;
    const scenario = args[0];
    const json = hasFlag(args[1..], "--json");
    const observation = fixture(scenario) orelse return error.UnknownScenario;
    const result = kz.detectors.evaluate(observation, .{});

    if (result) |finding| {
        if (json) {
            var buffer: [1024]u8 = undefined;
            const output = try std.fmt.bufPrint(
                &buffer,
                "{{\"schema_version\":\"kz/v1\",\"kind\":\"Finding\",\"detector\":\"{s}\",\"severity\":\"{s}\",\"namespace\":\"default\",\"resource\":\"{s}\",\"reason\":\"{s}\"}}\n",
                .{ finding.detector.label(), finding.severity.label(), finding.subject.name, finding.reason },
            );
            return write(output);
        }
        var buffer: [512]u8 = undefined;
        const output = try std.fmt.bufPrint(&buffer, "{s} {s}: {s}\n", .{
            finding.severity.label(), finding.detector.label(), finding.reason,
        });
        return write(output);
    }
    if (json) return write("{\"schema_version\":\"kz/v1\",\"kind\":\"FindingList\",\"items\":[]}\n");
    try write("healthy: no detector matched\n");
}

fn policyExample(args: []const []const u8) !void {
    var max_auto_risk: u8 = 0;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--auto-risk") and index + 1 < args.len) {
            max_auto_risk = std.fmt.parseInt(u8, args[index + 1], 10) catch return error.InvalidRisk;
            index += 1;
        }
    }
    const plan = kz.types.RemediationPlan{
        .action = .evict_pod,
        .target = .{
            .api_version = "v1",
            .kind = .pod,
            .namespace = "development",
            .name = "api-unhealthy",
            .uid = "pod-uid",
        },
        .target_class = .pod,
        .available_replicas = 3,
        .desired_replicas = 3,
        .cache_fresh = true,
        .target_uid_matches = true,
    };
    const decision = kz.policy.evaluate(plan, .{ .mutations_enabled = true, .max_auto_risk = max_auto_risk });
    var buffer: [256]u8 = undefined;
    const output = switch (decision) {
        .allow_auto => |score| try std.fmt.bufPrint(&buffer, "ALLOW_AUTO risk={d}\n", .{score}),
        .require_approval => |score| try std.fmt.bufPrint(&buffer, "REQUIRE_APPROVAL risk={d}\n", .{score}),
        .deny => |reason| try std.fmt.bufPrint(&buffer, "DENY reason={s}\n", .{@tagName(reason)}),
    };
    try write(output);
}

fn fixture(name: []const u8) ?kz.detectors.Observation {
    var observation = kz.detectors.Observation{
        .subject = .{
            .api_version = "v1",
            .kind = .pod,
            .namespace = "default",
            .name = "api-abc",
            .uid = "pod-1",
        },
        .root_owner_uid = "deployment-api",
    };
    if (std.mem.eql(u8, name, "healthy")) return observation;
    if (std.mem.eql(u8, name, "oom")) {
        observation.termination_reason = "OOMKilled";
        observation.restart_count = 3;
        return observation;
    }
    if (std.mem.eql(u8, name, "crashloop")) {
        observation.waiting_reason = "CrashLoopBackOff";
        observation.restart_count = 4;
        return observation;
    }
    if (std.mem.eql(u8, name, "image-pull")) {
        observation.waiting_reason = "ImagePullBackOff";
        return observation;
    }
    if (std.mem.eql(u8, name, "pending")) {
        observation.phase = "Pending";
        observation.pending_seconds = 180;
        observation.event_reason = "FailedScheduling";
        return observation;
    }
    if (std.mem.eql(u8, name, "service")) {
        observation.subject.kind = .service;
        observation.subject.name = "api";
        observation.selector_present = true;
        observation.endpoint_count = 0;
        return observation;
    }
    return null;
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |argument| if (std.mem.eql(u8, argument, flag)) return true;
    return false;
}

fn boolean(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn write(value: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(process_io, value);
}
