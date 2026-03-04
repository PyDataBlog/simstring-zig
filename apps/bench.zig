const std = @import("std");
const simstring = @import("simstring_zig");

const Stats = struct {
    mean: f64,
    stddev: f64,
    iterations: usize,
};

const Parameters = struct {
    ngram_size: usize,
    threshold: ?f64 = null,
};

const BenchmarkResult = struct {
    language: []const u8,
    backend: []const u8,
    benchmark: []const u8,
    parameters: Parameters,
    stats: Stats,
};

const Config = struct {
    dataset_path: []const u8 = "benches/data/company_names.txt",
    owns_dataset_path: bool = false,
    seconds: f64 = 3.0,
    max_iterations: usize = 50,
    reserve: bool = false,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const config = try parseArgs(allocator);
    defer if (config.owns_dataset_path) allocator.free(config.dataset_path);

    const dataset_bytes = try std.fs.cwd().readFileAlloc(allocator, config.dataset_path, 64 * 1024 * 1024);
    defer allocator.free(dataset_bytes);

    var companies: std.ArrayList([]const u8) = .empty;
    defer companies.deinit(allocator);
    try parseLines(allocator, dataset_bytes, &companies);

    var results: std.ArrayList(BenchmarkResult) = .empty;
    defer results.deinit(allocator);

    try benchInsert(
        allocator,
        companies.items,
        config.seconds,
        config.max_iterations,
        config.reserve,
        &results,
    );
    try benchSearch(
        allocator,
        companies.items,
        config.seconds,
        config.max_iterations,
        config.reserve,
        &results,
    );

    var out_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&out_buffer);
    const stdout = &stdout_writer.interface;
    try std.json.Stringify.value(results.items, .{ .whitespace = .indent_2 }, stdout);
    try stdout.writeAll("\n");
    try stdout.flush();
}

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var cfg = Config{};

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dataset")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            cfg.dataset_path = try allocator.dupe(u8, args[i + 1]);
            cfg.owns_dataset_path = true;
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--seconds")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            cfg.seconds = try std.fmt.parseFloat(f64, args[i + 1]);
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--iterations")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            cfg.max_iterations = try std.fmt.parseInt(usize, args[i + 1], 10);
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--reserve")) {
            cfg.reserve = true;
            i += 1;
            continue;
        }
        return error.InvalidArgs;
    }

    return cfg;
}

fn parseLines(allocator: std.mem.Allocator, bytes: []const u8, lines: *std.ArrayList([]const u8)) !void {
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trimRight(u8, line, "\r");
        if (trimmed.len == 0) continue;
        try lines.append(allocator, trimmed);
    }
}

fn benchInsert(
    allocator: std.mem.Allocator,
    companies: []const []const u8,
    seconds: f64,
    max_iterations: usize,
    reserve: bool,
    results: *std.ArrayList(BenchmarkResult),
) !void {
    const ngram_sizes = [_]usize{ 2, 3, 4 };

    for (ngram_sizes) |ngram_size| {
        const estimated_features = estimateFeaturesPerString(companies, ngram_size);
        var measurements: std.ArrayList(f64) = .empty;
        defer measurements.deinit(allocator);

        const suite_start = std.time.nanoTimestamp();
        var iteration: usize = 0;

        while (iteration < max_iterations) : (iteration += 1) {
            const now = std.time.nanoTimestamp();
            const elapsed = @as(f64, @floatFromInt(now - suite_start)) / 1_000_000_000.0;
            if (elapsed >= seconds) break;

            var db = simstring.HashDb.init(allocator, .{ .character = simstring.CharacterNgrams.init(ngram_size, " ") });
            defer db.deinit();
            if (reserve) {
                try db.reserveForWorkload(companies.len, estimated_features);
            }

            const start = std.time.nanoTimestamp();
            for (companies) |company| {
                try db.insert(company);
            }
            const end = std.time.nanoTimestamp();
            const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
            try measurements.append(allocator, elapsed_ms);
        }

        const stats = computeStats(measurements.items);
        try results.append(allocator, .{
            .language = "zig",
            .backend = "simstring-zig (native)",
            .benchmark = "insert",
            .parameters = .{ .ngram_size = ngram_size, .threshold = null },
            .stats = stats,
        });
    }
}

fn benchSearch(
    allocator: std.mem.Allocator,
    companies: []const []const u8,
    seconds: f64,
    max_iterations: usize,
    reserve: bool,
    results: *std.ArrayList(BenchmarkResult),
) !void {
    const ngram_sizes = [_]usize{ 2, 3, 4 };
    const thresholds = [_]f64{ 0.6, 0.7, 0.8, 0.9 };

    const max_terms = @min(companies.len, 100);
    const search_terms = companies[0..max_terms];

    for (ngram_sizes) |ngram_size| {
        const estimated_features = estimateFeaturesPerString(companies, ngram_size);
        var db = simstring.HashDb.init(allocator, .{ .character = simstring.CharacterNgrams.init(ngram_size, " ") });
        defer db.deinit();
        if (reserve) {
            try db.reserveForWorkload(companies.len, estimated_features);
        }

        for (companies) |company| {
            try db.insert(company);
        }

        var searcher = simstring.Searcher.init(allocator, &db, .cosine);

        for (thresholds) |threshold| {
            var measurements: std.ArrayList(f64) = .empty;
            defer measurements.deinit(allocator);

            const suite_start = std.time.nanoTimestamp();
            var iteration: usize = 0;

            while (iteration < max_iterations) : (iteration += 1) {
                const now = std.time.nanoTimestamp();
                const elapsed = @as(f64, @floatFromInt(now - suite_start)) / 1_000_000_000.0;
                if (elapsed >= seconds) break;

                const start = std.time.nanoTimestamp();
                for (search_terms) |term| {
                    const matches = try searcher.search(term, threshold);
                    allocator.free(matches);
                }
                const end = std.time.nanoTimestamp();

                const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
                try measurements.append(allocator, elapsed_ms);
            }

            const stats = computeStats(measurements.items);
            try results.append(allocator, .{
                .language = "zig",
                .backend = "simstring-zig (native)",
                .benchmark = "search",
                .parameters = .{ .ngram_size = ngram_size, .threshold = threshold },
                .stats = stats,
            });
        }
    }
}

fn computeStats(measurements: []const f64) Stats {
    if (measurements.len == 0) {
        return .{ .mean = 0.0, .stddev = 0.0, .iterations = 0 };
    }

    var sum: f64 = 0.0;
    for (measurements) |x| sum += x;
    const mean = sum / @as(f64, @floatFromInt(measurements.len));

    if (measurements.len == 1) {
        return .{ .mean = mean, .stddev = 0.0, .iterations = 1 };
    }

    var variance_sum: f64 = 0.0;
    for (measurements) |x| {
        const diff = mean - x;
        variance_sum += diff * diff;
    }

    const denom = @as(f64, @floatFromInt(measurements.len - 1));
    const variance = variance_sum / denom;

    return .{
        .mean = mean,
        .stddev = @sqrt(variance),
        .iterations = measurements.len,
    };
}

fn estimateFeaturesPerString(companies: []const []const u8, ngram_size: usize) usize {
    if (companies.len == 0) return ngram_size;
    const sample_count = @min(companies.len, 1000);

    var total_bytes: usize = 0;
    for (companies[0..sample_count]) |company| {
        total_bytes += company.len;
    }

    const avg_bytes = total_bytes / sample_count;
    const estimated = avg_bytes + ngram_size -| 1;
    return @max(@as(usize, 1), estimated);
}
