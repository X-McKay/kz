const std = @import("std");

pub const Severity = enum(u8) {
    info,
    warning,
    err,
    critical,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .info => "info",
            .warning => "warning",
            .err => "error",
            .critical => "critical",
        };
    }
};

pub const ResourceKind = enum {
    pod,
    deployment,
    stateful_set,
    daemon_set,
    node,
    persistent_volume_claim,
    service,
    job,
    other,
};

pub const ResourceRef = struct {
    cluster_id: []const u8 = "default",
    api_version: []const u8,
    kind: ResourceKind,
    namespace: ?[]const u8,
    name: []const u8,
    uid: []const u8,
    resource_version: []const u8 = "",
};

pub const DetectorKind = enum {
    pod_crash_loop,
    container_oom,
    image_pull_failure,
    pod_pending,
    pod_unschedulable,
    probe_failure,
    deployment_unavailable,
    rollout_stalled,
    stateful_set_stalled,
    daemon_set_unavailable,
    node_not_ready,
    node_pressure,
    pvc_pending,
    volume_mount_failure,
    service_no_endpoints,
    job_failed,

    pub fn label(self: DetectorKind) []const u8 {
        return switch (self) {
            .pod_crash_loop => "POD_CRASH_LOOP",
            .container_oom => "CONTAINER_OOM",
            .image_pull_failure => "IMAGE_PULL_FAILURE",
            .pod_pending => "POD_PENDING",
            .pod_unschedulable => "POD_UNSCHEDULABLE",
            .probe_failure => "PROBE_FAILURE",
            .deployment_unavailable => "DEPLOYMENT_UNAVAILABLE",
            .rollout_stalled => "ROLLOUT_STALLED",
            .stateful_set_stalled => "STATEFULSET_STALLED",
            .daemon_set_unavailable => "DAEMONSET_UNAVAILABLE",
            .node_not_ready => "NODE_NOT_READY",
            .node_pressure => "NODE_PRESSURE",
            .pvc_pending => "PVC_PENDING",
            .volume_mount_failure => "VOLUME_MOUNT_FAILURE",
            .service_no_endpoints => "SERVICE_NO_ENDPOINTS",
            .job_failed => "JOB_FAILED",
        };
    }
};

pub const FailureFamily = enum {
    workload_startup_failure,
    workload_runtime_failure,
    scheduling_failure,
    storage_failure,
    network_reachability_failure,
    node_failure,
    image_failure,
    configuration_failure,
    job_failure,
};

pub const Finding = struct {
    detector: DetectorKind,
    family: FailureFamily,
    severity: Severity,
    subject: ResourceRef,
    root_owner_uid: []const u8,
    reason: []const u8,
};

pub const IncidentState = enum {
    detected,
    debouncing,
    collecting,
    diagnosing,
    planned,
    needs_approval,
    auto_approved,
    executing,
    verifying,
    resolved,
    failed,
    rolled_back,
    escalated,
    reported,
};

pub const IncidentKey = struct {
    cluster_id: []const u8,
    namespace: []const u8,
    root_owner_uid: []const u8,
    family: FailureFamily,

    pub fn eql(a: IncidentKey, b: IncidentKey) bool {
        return std.mem.eql(u8, a.cluster_id, b.cluster_id) and
            std.mem.eql(u8, a.namespace, b.namespace) and
            std.mem.eql(u8, a.root_owner_uid, b.root_owner_uid) and
            a.family == b.family;
    }
};

pub const ActionKind = enum {
    no_action,
    escalate,
    evict_pod,
    restart_workload,
    scale_workload,
    patch_workload_resources,
};

pub const TargetClass = enum {
    stateless_workload,
    stateful_workload,
    pod,
    service,
    secret,
    rbac,
    network_policy,
    persistent_volume,
    namespace,
    node,
};

pub const RemediationPlan = struct {
    action: ActionKind,
    target: ResourceRef,
    target_class: TargetClass,
    fanout: u16 = 1,
    reversible: bool = true,
    available_replicas: u16 = 0,
    desired_replicas: u16 = 0,
    cache_fresh: bool,
    target_uid_matches: bool,
    dry_run_supported: bool = true,
    verification_required: bool = true,
};

test "incident keys correlate replacement pods by root owner" {
    const a = IncidentKey{
        .cluster_id = "c1",
        .namespace = "app",
        .root_owner_uid = "deployment-uid",
        .family = .workload_runtime_failure,
    };
    const b = a;
    try std.testing.expect(a.eql(b));
}
