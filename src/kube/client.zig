const std = @import("std");

pub const WatchState = struct {
    resource_version: []const u8 = "",
    synchronized: bool = false,
    stale: bool = true,

    pub fn listed(self: *WatchState, resource_version: []const u8) void {
        self.resource_version = resource_version;
        self.synchronized = true;
        self.stale = false;
    }

    pub fn watchDisconnected(self: *WatchState) void {
        _ = self;
        // A transport reconnect may continue from the last observed version.
    }

    pub fn resourceVersionExpired(self: *WatchState) void {
        self.stale = true;
        self.synchronized = false;
    }

    pub fn canAuthorizeMutation(self: WatchState) bool {
        return self.synchronized and !self.stale and self.resource_version.len > 0;
    }
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    dry_run: bool = false,
};

pub const Method = enum { get, list, watch, patch, post };

pub const PathError = error{ NoSpaceLeft, InvalidSegment };

pub fn namespacedPath(
    buffer: []u8,
    api_prefix: []const u8,
    namespace: []const u8,
    resource: []const u8,
    name: ?[]const u8,
) PathError![]const u8 {
    if (!safeSegment(namespace) or !safeSegment(resource) or (name != null and !safeSegment(name.?))) {
        return error.InvalidSegment;
    }
    if (name) |resource_name| {
        return std.fmt.bufPrint(buffer, "{s}/namespaces/{s}/{s}/{s}", .{ api_prefix, namespace, resource, resource_name }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buffer, "{s}/namespaces/{s}/{s}", .{ api_prefix, namespace, resource }) catch error.NoSpaceLeft;
}

fn safeSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    for (segment) |character| {
        if (!(std.ascii.isAlphanumeric(character) or character == '-' or character == '.' or character == '_')) return false;
    }
    return true;
}

test "410 recovery disables mutation until relist" {
    var state = WatchState{};
    state.listed("42");
    try std.testing.expect(state.canAuthorizeMutation());
    state.resourceVersionExpired();
    try std.testing.expect(!state.canAuthorizeMutation());
    state.listed("84");
    try std.testing.expect(state.canAuthorizeMutation());
}

test "resource names cannot inject a path" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(error.InvalidSegment, namespacedPath(&buffer, "/apis/apps/v1", "default", "deployments", "../secrets"));
}
