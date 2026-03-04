const std = @import("std");
const sim = @import("simstring_zig");

const Allocator = std.mem.Allocator;
const allocator: Allocator = std.heap.c_allocator;

const ExtractorKind = enum {
    character,
    word,
};

const DbHandle = struct {
    kind: ExtractorKind,
    endmarker: []u8,
    splitter: []u8,
    padder: []u8,
    db: sim.HashDb,
};

var last_error: [1024:0]u8 = [_:0]u8{0} ** 1024;

fn setLastError(msg: []const u8) void {
    const max_len = last_error.len - 1;
    const len = @min(msg.len, max_len);
    @memcpy(last_error[0..len], msg[0..len]);
    last_error[len] = 0;
    if (len + 1 < last_error.len) {
        @memset(last_error[len + 1 ..], 0);
    }
}

fn setLastErrorFmt(comptime fmt: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(last_error[0 .. last_error.len - 1], fmt, args) catch {
        setLastError("error formatting failure");
        return;
    };
    last_error[written.len] = 0;
    if (written.len + 1 < last_error.len) {
        @memset(last_error[written.len + 1 ..], 0);
    }
}

fn clearLastError() void {
    last_error[0] = 0;
}

fn toSlice(ptr: [*]const u8, len: usize) []const u8 {
    return ptr[0..len];
}

fn measureFromId(id: u32) ?sim.Measure {
    return switch (id) {
        0 => .cosine,
        1 => .dice,
        2 => .jaccard,
        3 => .overlap,
        4 => .exact_match,
        else => null,
    };
}

fn jsonCString(value: anytype) ?[*:0]u8 {
    const json = std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})}) catch {
        setLastError("failed to serialize JSON");
        return null;
    };
    defer allocator.free(json);

    const out = allocator.alloc(u8, json.len + 1) catch {
        setLastError("failed to allocate JSON string");
        return null;
    };
    @memcpy(out[0..json.len], json);
    out[json.len] = 0;
    return @ptrCast(out.ptr);
}

pub export fn sz_last_error() [*:0]const u8 {
    return @ptrCast(&last_error);
}

pub export fn sz_free_cstring(ptr: ?[*:0]u8) void {
    const p = ptr orelse return;
    const len = std.mem.len(p);
    allocator.free(p[0 .. len + 1]);
}

pub export fn sz_db_create_character(
    n: usize,
    endmarker_ptr: [*]const u8,
    endmarker_len: usize,
) ?*DbHandle {
    clearLastError();

    const endmarker = allocator.dupe(u8, toSlice(endmarker_ptr, endmarker_len)) catch {
        setLastError("failed to allocate endmarker");
        return null;
    };

    const handle = allocator.create(DbHandle) catch {
        allocator.free(endmarker);
        setLastError("failed to allocate db handle");
        return null;
    };

    handle.* = .{
        .kind = .character,
        .endmarker = endmarker,
        .splitter = &.{},
        .padder = &.{},
        .db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(n, endmarker) }),
    };

    return handle;
}

pub export fn sz_db_create_word(
    n: usize,
    splitter_ptr: [*]const u8,
    splitter_len: usize,
    padder_ptr: [*]const u8,
    padder_len: usize,
) ?*DbHandle {
    clearLastError();

    const splitter = allocator.dupe(u8, toSlice(splitter_ptr, splitter_len)) catch {
        setLastError("failed to allocate splitter");
        return null;
    };
    errdefer allocator.free(splitter);

    const padder = allocator.dupe(u8, toSlice(padder_ptr, padder_len)) catch {
        setLastError("failed to allocate padder");
        return null;
    };
    errdefer allocator.free(padder);

    const handle = allocator.create(DbHandle) catch {
        setLastError("failed to allocate db handle");
        return null;
    };

    handle.* = .{
        .kind = .word,
        .endmarker = &.{},
        .splitter = splitter,
        .padder = padder,
        .db = sim.HashDb.init(allocator, .{ .word = sim.WordNgrams.init(n, splitter, padder) }),
    };

    return handle;
}

pub export fn sz_db_destroy(handle: ?*DbHandle) void {
    const db_handle = handle orelse return;
    db_handle.db.deinit();
    switch (db_handle.kind) {
        .character => allocator.free(db_handle.endmarker),
        .word => {
            allocator.free(db_handle.splitter);
            allocator.free(db_handle.padder);
        },
    }
    allocator.destroy(db_handle);
}

pub export fn sz_db_insert(handle: ?*DbHandle, text_ptr: [*]const u8, text_len: usize) bool {
    clearLastError();
    const db_handle = handle orelse {
        setLastError("null db handle");
        return false;
    };

    db_handle.db.insert(toSlice(text_ptr, text_len)) catch |err| {
        setLastErrorFmt("insert failed: {s}", .{@errorName(err)});
        return false;
    };

    return true;
}

pub export fn sz_db_clear(handle: ?*DbHandle) bool {
    clearLastError();
    const db_handle = handle orelse {
        setLastError("null db handle");
        return false;
    };

    db_handle.db.clear();
    return true;
}

pub export fn sz_db_len(handle: ?*DbHandle) usize {
    const db_handle = handle orelse return 0;
    return db_handle.db.totalStrings();
}

pub export fn sz_db_strings_json(handle: ?*DbHandle) ?[*:0]u8 {
    clearLastError();
    const db_handle = handle orelse {
        setLastError("null db handle");
        return null;
    };

    return jsonCString(db_handle.db.strings.items);
}

pub export fn sz_search_json(
    handle: ?*DbHandle,
    measure_id: u32,
    query_ptr: [*]const u8,
    query_len: usize,
    alpha: f64,
) ?[*:0]u8 {
    clearLastError();
    const db_handle = handle orelse {
        setLastError("null db handle");
        return null;
    };

    const measure = measureFromId(measure_id) orelse {
        setLastError("invalid measure id");
        return null;
    };

    var searcher = sim.Searcher.init(allocator, &db_handle.db, measure);
    const matches = searcher.search(toSlice(query_ptr, query_len), alpha) catch |err| {
        setLastErrorFmt("search failed: {s}", .{@errorName(err)});
        return null;
    };
    defer allocator.free(matches);

    return jsonCString(matches);
}

pub export fn sz_ranked_search_json(
    handle: ?*DbHandle,
    measure_id: u32,
    query_ptr: [*]const u8,
    query_len: usize,
    alpha: f64,
) ?[*:0]u8 {
    clearLastError();
    const db_handle = handle orelse {
        setLastError("null db handle");
        return null;
    };

    const measure = measureFromId(measure_id) orelse {
        setLastError("invalid measure id");
        return null;
    };

    var searcher = sim.Searcher.init(allocator, &db_handle.db, measure);
    const matches = searcher.rankedSearch(toSlice(query_ptr, query_len), alpha) catch |err| {
        setLastErrorFmt("ranked search failed: {s}", .{@errorName(err)});
        return null;
    };
    defer allocator.free(matches);

    return jsonCString(matches);
}
