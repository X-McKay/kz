const std = @import("std");

pub const WorkloadObservation = struct {
    observed_generation: u64,
    target_generation: u64,
    desired_replicas: u16,
    available_replicas: u16,
    original_failure_present: bool,
    stable_for_seconds: u32,
};

pub const Contract = struct {
    stability_window_seconds: u32 = 120,
    require_original_failure_absent: bool = true,
};

pub fn workloadAvailable(observation: WorkloadObservation, contract: Contract) bool {
    if (observation.observed_generation < observation.target_generation) return false;
    if (observation.available_replicas != observation.desired_replicas) return false;
    if (contract.require_original_failure_absent and observation.original_failure_present) return false;
    return observation.stable_for_seconds >= contract.stability_window_seconds;
}

test "API acceptance is not remediation success" {
    try std.testing.expect(!workloadAvailable(.{
        .observed_generation = 4,
        .target_generation = 4,
        .desired_replicas = 3,
        .available_replicas = 3,
        .original_failure_present = true,
        .stable_for_seconds = 300,
    }, .{}));
}

test "verification requires a stability window" {
    try std.testing.expect(!workloadAvailable(.{
        .observed_generation = 4,
        .target_generation = 4,
        .desired_replicas = 3,
        .available_replicas = 3,
        .original_failure_present = false,
        .stable_for_seconds = 5,
    }, .{}));
}
