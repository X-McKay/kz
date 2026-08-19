const std = @import("std");
const types = @import("types.zig");
const policy = @import("policy.zig");

pub const Hypothesis = struct {
    cause: []const u8,
    confidence: f32,
    evidence_ids: []const []const u8,
};

pub const Proposal = struct {
    summary: []const u8,
    confidence: f32,
    hypotheses: []const Hypothesis,
    action: types.ActionKind,
    target_class: ?types.TargetClass = null,
    needs_more_evidence: bool = false,
};

pub const ValidationError = error{
    EmptySummary,
    InvalidConfidence,
    MissingHypothesis,
    MissingEvidenceCitation,
    UnknownEvidenceCitation,
    HardDeniedTarget,
};

/// Validates the model's typed proposal. This function has no API client and
/// therefore cannot perform a mutation by construction.
pub fn validate(proposal: Proposal, known_evidence_ids: []const []const u8) ValidationError!void {
    if (proposal.summary.len == 0) return error.EmptySummary;
    if (proposal.confidence < 0 or proposal.confidence > 1) return error.InvalidConfidence;
    if (!proposal.needs_more_evidence and proposal.hypotheses.len == 0) return error.MissingHypothesis;

    for (proposal.hypotheses) |hypothesis| {
        if (hypothesis.confidence < 0 or hypothesis.confidence > 1) return error.InvalidConfidence;
        if (hypothesis.evidence_ids.len == 0) return error.MissingEvidenceCitation;
        for (hypothesis.evidence_ids) |evidence_id| {
            if (!contains(known_evidence_ids, evidence_id)) return error.UnknownEvidenceCitation;
        }
    }
    if (proposal.target_class) |target| {
        if (policy.isHardDenied(target)) return error.HardDeniedTarget;
    }
}

fn contains(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, needle)) return true;
    return false;
}

test "hallucinated evidence is rejected" {
    const hypotheses = [_]Hypothesis{.{
        .cause = "memory pressure",
        .confidence = 0.9,
        .evidence_ids = &.{"ev-invented"},
    }};
    const proposal = Proposal{
        .summary = "pod was OOMKilled",
        .confidence = 0.9,
        .hypotheses = &hypotheses,
        .action = .patch_workload_resources,
        .target_class = .stateless_workload,
    };
    try std.testing.expectError(error.UnknownEvidenceCitation, validate(proposal, &.{"ev-1"}));
}

test "model cannot target a secret" {
    const hypotheses = [_]Hypothesis{.{
        .cause = "configuration",
        .confidence = 0.7,
        .evidence_ids = &.{"ev-1"},
    }};
    const proposal = Proposal{
        .summary = "model proposed forbidden target",
        .confidence = 0.7,
        .hypotheses = &hypotheses,
        .action = .patch_workload_resources,
        .target_class = .secret,
    };
    try std.testing.expectError(error.HardDeniedTarget, validate(proposal, &.{"ev-1"}));
}
