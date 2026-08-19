const std = @import("std");
const types = @import("types.zig");

pub const Observation = struct {
    subject: types.ResourceRef,
    root_owner_uid: []const u8 = "",
    phase: []const u8 = "",
    waiting_reason: []const u8 = "",
    termination_reason: []const u8 = "",
    event_reason: []const u8 = "",
    restart_count: u32 = 0,
    pending_seconds: u32 = 0,
    ready: bool = true,
    desired_replicas: u16 = 0,
    available_replicas: u16 = 0,
    progress_deadline_exceeded: bool = false,
    node_pressure: bool = false,
    pvc_pending_seconds: u32 = 0,
    endpoint_count: u16 = 1,
    selector_present: bool = false,
    job_failed: bool = false,
};

pub const Config = struct {
    crash_loop_min_restarts: u32 = 3,
    pod_pending_threshold_seconds: u32 = 120,
    pvc_pending_threshold_seconds: u32 = 120,
};

/// Evaluates the highest-specificity deterministic detector. The event loop may
/// call this again for materially different signals; incidents deduplicate them.
pub fn evaluate(observation: Observation, config: Config) ?types.Finding {
    const owner = if (observation.root_owner_uid.len > 0)
        observation.root_owner_uid
    else
        observation.subject.uid;

    if (std.mem.eql(u8, observation.termination_reason, "OOMKilled")) {
        return finding(observation, owner, .container_oom, .workload_runtime_failure, .err, "container terminated with OOMKilled");
    }
    if ((std.mem.eql(u8, observation.waiting_reason, "CrashLoopBackOff") and observation.restart_count >= config.crash_loop_min_restarts)) {
        return finding(observation, owner, .pod_crash_loop, .workload_runtime_failure, .err, "container is repeatedly restarting");
    }
    if (std.mem.eql(u8, observation.waiting_reason, "ErrImagePull") or
        std.mem.eql(u8, observation.waiting_reason, "ImagePullBackOff") or
        std.mem.eql(u8, observation.event_reason, "FailedPull"))
    {
        return finding(observation, owner, .image_pull_failure, .image_failure, .err, "container image cannot be pulled");
    }
    if (observation.subject.kind == .pod and
        std.mem.eql(u8, observation.phase, "Pending") and
        observation.pending_seconds >= config.pod_pending_threshold_seconds)
    {
        if (std.mem.eql(u8, observation.event_reason, "FailedScheduling")) {
            return finding(observation, owner, .pod_unschedulable, .scheduling_failure, .err, "pod is unschedulable beyond threshold");
        }
        return finding(observation, owner, .pod_pending, .scheduling_failure, .warning, "pod is pending beyond threshold");
    }
    if (observation.subject.kind == .deployment and observation.available_replicas < observation.desired_replicas) {
        if (observation.progress_deadline_exceeded) {
            return finding(observation, owner, .rollout_stalled, .workload_startup_failure, .err, "deployment exceeded its progress deadline");
        }
        return finding(observation, owner, .deployment_unavailable, .workload_startup_failure, .err, "deployment has unavailable replicas");
    }
    if (observation.subject.kind == .node and !observation.ready) {
        return finding(observation, owner, .node_not_ready, .node_failure, .critical, "node Ready condition is false or unknown");
    }
    if (observation.subject.kind == .node and observation.node_pressure) {
        return finding(observation, owner, .node_pressure, .node_failure, .err, "node reports resource pressure");
    }
    if (observation.subject.kind == .persistent_volume_claim and observation.pvc_pending_seconds >= config.pvc_pending_threshold_seconds) {
        return finding(observation, owner, .pvc_pending, .storage_failure, .err, "persistent volume claim is pending beyond threshold");
    }
    if (std.mem.eql(u8, observation.event_reason, "FailedMount") or std.mem.eql(u8, observation.event_reason, "FailedAttachVolume")) {
        return finding(observation, owner, .volume_mount_failure, .storage_failure, .err, "volume attachment or mount failed");
    }
    if (observation.subject.kind == .service and observation.selector_present and observation.endpoint_count == 0) {
        return finding(observation, owner, .service_no_endpoints, .network_reachability_failure, .err, "service has no ready endpoints");
    }
    if (observation.subject.kind == .job and observation.job_failed) {
        return finding(observation, owner, .job_failed, .job_failure, .err, "job has a failed condition");
    }
    return null;
}

fn finding(
    observation: Observation,
    owner: []const u8,
    detector: types.DetectorKind,
    family: types.FailureFamily,
    severity: types.Severity,
    reason: []const u8,
) types.Finding {
    return .{
        .detector = detector,
        .family = family,
        .severity = severity,
        .subject = observation.subject,
        .root_owner_uid = owner,
        .reason = reason,
    };
}

fn podRef() types.ResourceRef {
    return .{
        .api_version = "v1",
        .kind = .pod,
        .namespace = "default",
        .name = "api-abc",
        .uid = "pod-1",
    };
}

test "OOM is more specific than crash loop" {
    const result = evaluate(.{
        .subject = podRef(),
        .root_owner_uid = "deploy-1",
        .waiting_reason = "CrashLoopBackOff",
        .termination_reason = "OOMKilled",
        .restart_count = 5,
    }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.container_oom, result.detector);
}

test "one transient restart is ignored" {
    try std.testing.expect(evaluate(.{
        .subject = podRef(),
        .waiting_reason = "CrashLoopBackOff",
        .restart_count = 1,
    }, .{}) == null);
}

test "failed scheduling becomes a bounded incident" {
    const result = evaluate(.{
        .subject = podRef(),
        .phase = "Pending",
        .pending_seconds = 180,
        .event_reason = "FailedScheduling",
    }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.pod_unschedulable, result.detector);
}

test "stalled rollout outranks generic deployment unavailability" {
    var subject = podRef();
    subject.kind = .deployment;
    const result = evaluate(.{
        .subject = subject,
        .desired_replicas = 3,
        .available_replicas = 1,
        .progress_deadline_exceeded = true,
    }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.rollout_stalled, result.detector);
}

test "node not ready is critical" {
    var subject = podRef();
    subject.kind = .node;
    subject.namespace = null;
    const result = evaluate(.{ .subject = subject, .ready = false }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.node_not_ready, result.detector);
    try std.testing.expectEqual(types.Severity.critical, result.severity);
}

test "pending PVC matches storage detector" {
    var subject = podRef();
    subject.kind = .persistent_volume_claim;
    const result = evaluate(.{ .subject = subject, .pvc_pending_seconds = 180 }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.pvc_pending, result.detector);
}

test "failed mount event matches storage detector" {
    const result = evaluate(.{ .subject = podRef(), .event_reason = "FailedMount" }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.volume_mount_failure, result.detector);
}

test "service with selector and no endpoint matches" {
    var subject = podRef();
    subject.kind = .service;
    const result = evaluate(.{
        .subject = subject,
        .selector_present = true,
        .endpoint_count = 0,
    }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.service_no_endpoints, result.detector);
}

test "failed job matches" {
    var subject = podRef();
    subject.kind = .job;
    const result = evaluate(.{ .subject = subject, .job_failed = true }, .{}).?;
    try std.testing.expectEqual(types.DetectorKind.job_failed, result.detector);
}
