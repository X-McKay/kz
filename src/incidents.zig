const std = @import("std");
const types = @import("types.zig");

pub fn keyFor(finding: types.Finding) types.IncidentKey {
    return .{
        .cluster_id = finding.subject.cluster_id,
        .namespace = finding.subject.namespace orelse "",
        .root_owner_uid = finding.root_owner_uid,
        .family = finding.family,
    };
}

pub fn canTransition(from: types.IncidentState, to: types.IncidentState) bool {
    return switch (from) {
        .detected => to == .debouncing or to == .collecting,
        .debouncing => to == .collecting,
        .collecting => to == .diagnosing or to == .reported,
        .diagnosing => to == .planned or to == .reported or to == .escalated,
        .planned => to == .needs_approval or to == .auto_approved or to == .reported,
        .needs_approval => to == .executing or to == .reported or to == .escalated,
        .auto_approved => to == .executing,
        .executing => to == .verifying or to == .failed,
        .verifying => to == .resolved or to == .failed or to == .rolled_back or to == .escalated,
        .failed => to == .collecting or to == .rolled_back or to == .escalated,
        .rolled_back => to == .escalated or to == .reported,
        .resolved, .escalated, .reported => false,
    };
}

pub const AttemptBudget = struct {
    max_attempts: u8 = 2,
    attempts: u8 = 0,

    pub fn consume(self: *AttemptBudget) bool {
        if (self.attempts >= self.max_attempts) return false;
        self.attempts += 1;
        return true;
    }
};

test "incident lifecycle rejects mutation before planning" {
    try std.testing.expect(!canTransition(.detected, .executing));
    try std.testing.expect(canTransition(.planned, .needs_approval));
    try std.testing.expect(!canTransition(.resolved, .executing));
}

test "attempt budget is bounded" {
    var budget = AttemptBudget{ .max_attempts = 2 };
    try std.testing.expect(budget.consume());
    try std.testing.expect(budget.consume());
    try std.testing.expect(!budget.consume());
}
