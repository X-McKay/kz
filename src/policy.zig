const std = @import("std");
const types = @import("types.zig");

pub const Decision = union(enum) {
    allow_auto: u8,
    require_approval: u8,
    deny: DenyReason,
};

pub const DenyReason = enum {
    hard_denied_target,
    stale_cache,
    stale_plan,
    missing_verification,
    unsupported_dry_run,
    availability_precondition,
    mutations_disabled,
};

pub const Config = struct {
    mutations_enabled: bool = false,
    max_auto_risk: u8 = 0,
};

pub fn risk(plan: types.RemediationPlan) u8 {
    var score: u8 = switch (plan.action) {
        .no_action, .escalate => 0,
        .evict_pod => 1,
        .restart_workload => 2,
        .scale_workload => 3,
        .patch_workload_resources => 4,
    };

    const target_score: u8 = switch (plan.target_class) {
        .stateless_workload, .pod => 0,
        .service => 5,
        .stateful_workload => 6,
        .node => 7,
        .secret, .rbac, .network_policy => 8,
        .persistent_volume, .namespace => 9,
    };
    score = @max(score, target_score);
    if (plan.fanout > 1) score = @max(score, 3);
    if (!plan.reversible) score = @min(@as(u8, 10), score + 1);
    return score;
}

pub fn evaluate(plan: types.RemediationPlan, config: Config) Decision {
    if (isHardDenied(plan.target_class)) return .{ .deny = .hard_denied_target };
    if (plan.action == .no_action or plan.action == .escalate) return .{ .allow_auto = 0 };
    if (!config.mutations_enabled) return .{ .deny = .mutations_disabled };
    if (!plan.cache_fresh) return .{ .deny = .stale_cache };
    if (!plan.target_uid_matches) return .{ .deny = .stale_plan };
    if (!plan.verification_required) return .{ .deny = .missing_verification };
    if (!plan.dry_run_supported) return .{ .deny = .unsupported_dry_run };
    if (plan.action == .evict_pod and plan.desired_replicas > 1 and plan.available_replicas < 2) {
        return .{ .deny = .availability_precondition };
    }

    const score = risk(plan);
    if (score <= config.max_auto_risk) return .{ .allow_auto = score };
    return .{ .require_approval = score };
}

pub fn isHardDenied(target: types.TargetClass) bool {
    return switch (target) {
        .secret, .rbac, .network_policy, .persistent_volume, .namespace => true,
        else => false,
    };
}

fn planFor(target: types.TargetClass) types.RemediationPlan {
    return .{
        .action = .evict_pod,
        .target = .{
            .api_version = "v1",
            .kind = .pod,
            .namespace = "development",
            .name = "api-1",
            .uid = "pod-1",
        },
        .target_class = target,
        .available_replicas = 3,
        .desired_replicas = 3,
        .cache_fresh = true,
        .target_uid_matches = true,
    };
}

test "fresh single pod eviction can be auto-allowed by explicit policy" {
    const decision = evaluate(planFor(.pod), .{ .mutations_enabled = true, .max_auto_risk = 1 });
    try std.testing.expectEqual(@as(u8, 1), decision.allow_auto);
}

test "read-only is the default" {
    const decision = evaluate(planFor(.pod), .{});
    try std.testing.expectEqual(DenyReason.mutations_disabled, decision.deny);
}

test "hard-denied target ignores permissive threshold" {
    const decision = evaluate(planFor(.secret), .{ .mutations_enabled = true, .max_auto_risk = 10 });
    try std.testing.expectEqual(DenyReason.hard_denied_target, decision.deny);
}

test "stale cache fails closed" {
    var plan = planFor(.pod);
    plan.cache_fresh = false;
    const decision = evaluate(plan, .{ .mutations_enabled = true, .max_auto_risk = 10 });
    try std.testing.expectEqual(DenyReason.stale_cache, decision.deny);
}

test "risk above threshold requires approval" {
    var plan = planFor(.stateless_workload);
    plan.action = .patch_workload_resources;
    const decision = evaluate(plan, .{ .mutations_enabled = true, .max_auto_risk = 1 });
    try std.testing.expectEqual(@as(u8, 4), decision.require_approval);
}

test "eviction cannot reduce the last available replica" {
    var plan = planFor(.pod);
    plan.desired_replicas = 3;
    plan.available_replicas = 1;
    const decision = evaluate(plan, .{ .mutations_enabled = true, .max_auto_risk = 10 });
    try std.testing.expectEqual(DenyReason.availability_precondition, decision.deny);
}

test "missing verification contract fails closed" {
    var plan = planFor(.pod);
    plan.verification_required = false;
    const decision = evaluate(plan, .{ .mutations_enabled = true, .max_auto_risk = 10 });
    try std.testing.expectEqual(DenyReason.missing_verification, decision.deny);
}
