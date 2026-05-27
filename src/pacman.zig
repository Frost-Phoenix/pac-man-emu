// ********** imports ********** //

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

const Z80 = @import("zig80");

// ********** constants ********** //

const NB_TILE = 256;
const TILE_SIZE = 8;
const PIXEL_PER_TILE = TILE_SIZE * TILE_SIZE;

const SPRITE_SIZE = 16;

const BYTE_PER_PIXEL = 3;

const SCREEN_TILE_WIDTH = 28;
const SCREEN_TILE_HEIGHT = 36;

pub const SCREEN_WIDTH = SCREEN_TILE_WIDTH * TILE_SIZE;
pub const SCREEN_HEIGHT = SCREEN_TILE_HEIGHT * TILE_SIZE;

const CLOCK_SPEED = 3_072_000; // 3.072 MHz
const FPS = 60; // suposed to be 60.61
const CYCLES_PER_FRAMES = CLOCK_SPEED / FPS;

// ********** global vars ********** //

var cpu: Z80 = .init(.{
    .memRead = memRead,
    .memWrite = memWrite,
    .ioRead = ioRead,
    .ioWrite = ioWrite,
});

var memory: [65536]u8 = @splat(0);

var tile_rom: [4096]u8 = undefined;
var sprite_rom: [4096]u8 = undefined;

var color_rom: [32]u8 = undefined;
var palette_rom: [256]u8 = undefined;

var colors: [32]Color = undefined;
var palettes: [64][4]u8 = undefined;
var tiles: [NB_TILE][PIXEL_PER_TILE]u2 = undefined;

// ********** types ********** //

const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    fn init(r: u8, g: u8, b: u8) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
        };
    }
};

// ********** callback functions ********** //

fn memRead(addr: u16) u8 {
    return memory[addr];
}

fn memWrite(addr: u16, data: u8) void {
    memory[addr] = data;
}

fn ioRead(addr: u16) u8 {
    _ = addr;

    return 0x00;
}

fn ioWrite(addr: u16, data: u8) void {
    _ = addr;
    _ = data;
}

// ********** public functions ********** //

pub fn init(io: Io) !void {
    try loadRoms(io);

    loadColors();
    loadPalettes();
    loadTiles();
}

pub fn runNextFrame() void {
    for (0..CYCLES_PER_FRAMES) |_| {
        cpu.step();
    }
}

pub fn getCycles() u64 {
    return cpu.cycles;
}

// ********** private functions ********** //

fn loadRoms(io: Io) !void {
    const base_path = "./roms/midway/";
    const rom_names = enum {
        @"pacman.6e", // code rom 1
        @"pacman.6f", // code rom 2
        @"pacman.6h", // code rom 3
        @"pacman.6j", // code rom 4
        @"pacman.5e", // tile rom
        @"pacman.5f", // sprite rom
        @"82s123.7f", // color rom
        @"82s126.4a", // palette rom
    };

    const cwd = Dir.cwd();

    inline for (std.enums.values(rom_names), 0..) |rom_name, i| {
        const rom_path = base_path ++ @tagName(rom_name);

        var buff: [4096]u8 = undefined;
        const data = try cwd.readFile(io, rom_path, &buff);

        switch (rom_name) {
            .@"pacman.6e", .@"pacman.6f", .@"pacman.6h", .@"pacman.6j" => {
                const start_addr = i * 4096;
                const end_addr = start_addr + 4096;

                @memcpy(memory[start_addr..end_addr], data);
            },
            .@"pacman.5e" => @memcpy(tile_rom[0..tile_rom.len], data),
            .@"pacman.5f" => @memcpy(sprite_rom[0..sprite_rom.len], data),
            .@"82s123.7f" => @memcpy(color_rom[0..color_rom.len], data),
            .@"82s126.4a" => @memcpy(palette_rom[0..palette_rom.len], data),
        }
    }
}

fn loadColors() void {
    for (color_rom, 0..) |byte, i| {
        var r = byte & 0b111;
        var g = (byte >> 3) & 0b111;
        var b = (byte >> 6) & 0b11;

        r = 0x21 * (r & 0b001) + 0x47 * ((r & 0b010) >> 1) + 0x97 * ((r & 0b100) >> 2);
        g = 0x21 * (g & 0b001) + 0x47 * ((g & 0b010) >> 1) + 0x97 * ((g & 0b100) >> 2);
        b = 0x51 * (b & 0b01) + 0xae * ((b & 0b10) >> 1);

        colors[i] = .init(r, g, b);
    }
}

fn loadPalettes() void {
    const BYTE_PER_PALETTE = 4;

    for (0..64) |palette_id| {
        const idx = palette_id * BYTE_PER_PALETTE;
        const palette = palette_rom[idx .. idx + BYTE_PER_PALETTE];

        @memcpy(&palettes[palette_id], palette);
    }
}

fn loadTiles() void {
    for (0..NB_TILE) |id| {
        decodeTile(id);
    }
}

fn decodeTile(tile_id: usize) void {
    const TILE_BYTES = 16;

    const tile_addr = tile_id * TILE_BYTES;
    const tile_data = tile_rom[tile_addr .. tile_addr + TILE_BYTES];

    for (tile_data, 0..) |byte, i| {
        const lower_bits: u4 = @truncate(byte & 0x0f);
        const upper_bits: u4 = @truncate(byte >> 4);

        const offest: usize = if (i >= TILE_BYTES / 2) 0 else TILE_SIZE / 2;

        for (0..4) |j| {
            const bit_idx: u2 = @intCast(j);
            const mask: u4 = @as(u4, 0b1) << bit_idx;

            const lsb = (lower_bits & mask) >> bit_idx;
            const msb = (upper_bits & mask) >> bit_idx;

            const pixel: u2 = @truncate((msb << 1) | lsb);

            const x = TILE_SIZE - (i % TILE_SIZE) - 1;
            const y = 3 - j + offest;

            const idx = y * TILE_SIZE + x;

            tiles[tile_id][idx] = pixel;
        }
    }
}

// ********** debug functions ********** //

pub fn dumpMemory(io: Io) !void {
    const cwd = Dir.cwd();

    try cwd.createDirPath(io, "dump");

    try cwd.writeFile(io, .{ .data = &memory, .sub_path = "dump/memory.bin" });
    try cwd.writeFile(io, .{ .data = &sprite_rom, .sub_path = "dump/sprite.bin" });
    try cwd.writeFile(io, .{ .data = &tile_rom, .sub_path = "dump/tile.bin" });
    try cwd.writeFile(io, .{ .data = &color_rom, .sub_path = "dump/color.bin" });
    try cwd.writeFile(io, .{ .data = &palette_rom, .sub_path = "dump/palette.bin" });
}

pub fn renderTileMap(alloc: Allocator) ![]u8 {
    var buffer = try alloc.alloc(u8, NB_TILE * PIXEL_PER_TILE * BYTE_PER_PIXEL);

    const palette = palettes[1];

    for (0..16) |row| {
        for (0..16) |col| {
            const id = row * 16 + col;
            const base_idx = (row * 16 * PIXEL_PER_TILE + col * TILE_SIZE) * BYTE_PER_PIXEL;

            const tile = tiles[id];

            for (tile, 0..) |pixel, i| {
                const color_id = palette[pixel];
                const color = colors[color_id];

                const x = i % TILE_SIZE;
                const y = i / TILE_SIZE;

                const idx = base_idx + (y * 16 * TILE_SIZE * 3) + (x * 3);

                buffer[idx + 0] = color.r;
                buffer[idx + 1] = color.g;
                buffer[idx + 2] = color.b;
            }
        }
    }

    return buffer;
}
