// ********** imports ********** //

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

// ********** constants ********** //

const TILE_SIZE = 8;
const SPRITE_SIZE = 16;

const SCREEN_TILE_WIDTH = 28;
const SCREEN_TILE_HEIGHT = 36;

pub const SCREEN_WIDTH = SCREEN_TILE_WIDTH * TILE_SIZE;
pub const SCREEN_HEIGHT = SCREEN_TILE_HEIGHT * TILE_SIZE;

// ********** types ********** //

pub const PacMan = struct {
    const Self = @This();

    memory: [65536]u8,

    tile_rom: [4096]u8,
    sprite_rom: [4096]u8,

    color_rom: [32]u8,
    palette_rom: [256]u8,

    pub fn init(io: Io) !Self {
        var pac: Self = undefined;

        try pac.loadRoms(io);

        return pac;
    }

    fn loadRoms(self: *Self, io: Io) !void {
        const base_path = "./roms/midway/";
        const rom_names = [_][]const u8{
            "pacman.6e", // code rom 1
            "pacman.6f", // code rom 2
            "pacman.6h", // code rom 3
            "pacman.6j", // code rom 4
            "pacman.5e", // tile rom
            "pacman.5f", // sprite rom
            "82s123.7f", // color rom
            "82s126.4a", // palette rom
        };

        const cwd = Dir.cwd();

        inline for (rom_names, 0..) |rom_name, i| {
            const rom_path = base_path ++ rom_name;

            var buff: [4096]u8 = undefined;
            const data = try cwd.readFile(io, rom_path, &buff);

            switch (i) {
                0...3 => {
                    const start_addr = i * 4096;
                    const end_addr = start_addr + 4096;

                    @memcpy(self.memory[start_addr..end_addr], data);
                },
                4 => @memcpy(self.tile_rom[0..self.tile_rom.len], data),
                5 => @memcpy(self.sprite_rom[0..self.sprite_rom.len], data),
                6 => @memcpy(self.color_rom[0..self.color_rom.len], data),
                7 => @memcpy(self.palette_rom[0..self.palette_rom.len], data),
                else => unreachable,
            }
        }
    }

    pub fn dumpMemory(self: *Self, io: Io) !void {
        const cwd = Dir.cwd();

        try cwd.writeFile(io, .{ .data = &self.memory, .sub_path = "memory.bin" });
        try cwd.writeFile(io, .{ .data = &self.sprite_rom, .sub_path = "sprite.bin" });
        try cwd.writeFile(io, .{ .data = &self.tile_rom, .sub_path = "tile.bin" });
        try cwd.writeFile(io, .{ .data = &self.color_rom, .sub_path = "color.bin" });
        try cwd.writeFile(io, .{ .data = &self.palette_rom, .sub_path = "palette.bin" });
    }
};
