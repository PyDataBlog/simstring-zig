const std = @import("std");
const interner_mod = @import("../core/interner.zig");
const types = @import("../core/types.zig");

pub const CharacterNgrams = @import("character_ngrams.zig").CharacterNgrams;
pub const WordNgrams = @import("word_ngrams.zig").WordNgrams;

pub const FeatureExtractor = union(enum) {
    character: CharacterNgrams,
    word: WordNgrams,

    pub fn features(
        self: FeatureExtractor,
        allocator: std.mem.Allocator,
        text: []const u8,
        interner: *interner_mod.FeatureInterner,
    ) ![]types.FeatureId {
        return switch (self) {
            .character => |extractor| extractor.features(allocator, text, interner),
            .word => |extractor| extractor.features(allocator, text, interner),
        };
    }
};
