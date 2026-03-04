const std = @import("std");

pub const types = @import("core/types.zig");
pub const interner = @import("core/interner.zig");
pub const extractors = @import("extractors/mod.zig");
pub const database = @import("database/mod.zig");
pub const measures = @import("measures/mod.zig");
pub const search = @import("search.zig");

pub const StringId = types.StringId;
pub const FeatureId = types.FeatureId;
pub const RawFeatureId = types.RawFeatureId;
pub const SimstringError = types.SimstringError;
pub const RankedMatch = types.RankedMatch;

pub const FeatureInterner = interner.FeatureInterner;

pub const CharacterNgrams = extractors.CharacterNgrams;
pub const WordNgrams = extractors.WordNgrams;
pub const FeatureExtractor = extractors.FeatureExtractor;

pub const HashDb = database.HashDb;

pub const Measure = measures.Measure;

pub const Searcher = search.Searcher;

test {
    std.testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
