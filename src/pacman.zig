// ********** imports ********** //

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

const Z80 = @import("zig80");

// ********** constants ********** //

const TILE_NB = 256;
const TILE_SIZE = 8;
const TILE_NB_PIXEL = TILE_SIZE * TILE_SIZE;

const SPRITE_NB = 64;
const SPRITE_SIZE = 16;
const SPRITE_NB_PIXEL = SPRITE_SIZE * SPRITE_SIZE;

const BYTE_PER_PIXEL = 3;

const SCREEN_TILE_WIDTH = 28;
const SCREEN_TILE_HEIGHT = 36;

pub const SCREEN_WIDTH = SCREEN_TILE_WIDTH * TILE_SIZE;
pub const SCREEN_HEIGHT = SCREEN_TILE_HEIGHT * TILE_SIZE;

const FPS = 60.61;
const CLOCK_SPEED = 3_072_000; // 3.072 MHz
const CYCLES_PER_FRAMES = @divTrunc(CLOCK_SPEED, FPS);

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

var tiles: [TILE_NB][TILE_NB_PIXEL]u2 = undefined;
var sprites: [SPRITE_NB][SPRITE_NB_PIXEL]u2 = undefined;

pub var frame_buffer: [SCREEN_WIDTH * SCREEN_HEIGHT * BYTE_PER_PIXEL]u8 = undefined;

var vblank_enabled: bool = false;
var vblank_data: u8 = 0;

var in0: IN0 = .init();
var in1: IN1 = .init();

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

const IN0 = packed struct(u8) {
    up: u1 = 1,
    left: u1 = 1,
    right: u1 = 1,
    down: u1 = 1,
    rack_advance: u1 = 1,
    coin_slot_1: u1 = 0,
    coin_slot_2: u1 = 0,
    credit_button: u1 = 1,

    fn init() IN0 {
        return IN0{};
    }

    fn getByte(self: IN0) u8 {
        return @bitCast(self);
    }
};

const IN1 = packed struct(u8) {
    p2_up: u1 = 1,
    p2_left: u1 = 1,
    p2_right: u1 = 1,
    p2_down: u1 = 1,
    board_test: u1 = 1,
    p1_start: u1 = 1,
    p2_start: u1 = 1,
    cabinet_mode: u1 = 1,

    fn init() IN1 {
        return IN1{};
    }

    fn getByte(self: IN1) u8 {
        return @bitCast(self);
    }
};

// ********** callback functions ********** //

fn memRead(addr: u16) u8 {
    return switch (addr) {
        0x0000...0x4FFF => memory[addr],
        0x5000...0x503f => in0.getByte(), // IN0
        0x5040...0x507f => in1.getByte(), // IN1
        0x5080...0x50bf => 0xff, // DIP switch

        else => {
            std.log.err("Invalid read at: 0x{x:0>4}", .{addr});
            return 0xff;
        },
    };
}

fn memWrite(addr: u16, data: u8) void {
    const clamped_addr = addr & 0x7fff; // no a15 address line

    switch (clamped_addr) {
        0x0000...0x3fff => std.log.err("Trying to write ROM at: 0x{x:0>4}", .{clamped_addr}),
        0x4000...0x4fff => memory[clamped_addr] = data,
        0x5000 => vblank_enabled = data & 0b1 == 1,
        0x5001 => std.log.warn("Sound enable write", .{}),
        0x5002 => std.log.warn("Aux board enable write", .{}),
        0x5003 => std.log.warn("Flip screen write", .{}),
        0x5004 => std.log.warn("player 1 start light write", .{}),
        0x5005 => std.log.warn("player 2 start light write", .{}),
        0x5006 => std.log.warn("Coin lockout write", .{}),
        0x5007 => std.log.warn("Coin counter write", .{}),
        0x5040...0x505f => std.log.warn("Sound registers write", .{}),
        0x5060...0x506f => std.log.warn("Sprite coordinates write", .{}),
        0x50C0...0x50ff => {}, // std.log.warn("Watchdog timer write", .{}),

        else => std.log.err("Invalid write at: 0x{x:0>4}", .{clamped_addr}),
    }
}

fn ioRead(addr: u16) u8 {
    const port: u8 = @truncate(addr & 0xff);

    std.log.err("IO read on port: {}", .{port});

    return 0x00;
}

fn ioWrite(addr: u16, data: u8) void {
    const port: u8 = @truncate(addr & 0xff);

    if (port == 0) {
        vblank_data = data;
    } else {
        std.log.err("IO write on port: {}", .{port});
    }
}

// ********** public functions ********** //

pub fn init(io: Io) !void {
    try loadRoms(io);

    loadColors();
    loadPalettes();
    loadTiles();
    loadSprites();
}

pub fn runNextFrame() void {
    while (cpu.cycles < CYCLES_PER_FRAMES) {
        cpu.step();
    }
    cpu.cycles -= CYCLES_PER_FRAMES;

    renderFrame();

    if (vblank_enabled) {
        cpu.requestINT(vblank_data);
    }
}

pub fn getCycles() u64 {
    return cpu.cycles;
}

// ********** private functions ********** //

fn loadRoms(io: Io) !void {
    const base_path = "./roms/midway/";
    // const base_path = "./roms/hello/";
    // const base_path = "./roms/matrix/";

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
    for (0..TILE_NB) |id| {
        decodeTile(id);
    }
}

fn decodeTile(tile_id: usize) void {
    const TILE_BYTES = 16;

    const tile = &tiles[tile_id];
    const tile_addr = tile_id * TILE_BYTES;
    const tile_data = tile_rom[tile_addr .. tile_addr + TILE_BYTES];

    for (tile_data, 0..) |byte, i| {
        const offest: usize = if (i >= TILE_BYTES / 2) 0 else TILE_SIZE / 2;

        const x = TILE_SIZE - (i % TILE_SIZE) - 1;
        const y = TILE_SIZE / 2 + offest - 1;

        const idx = y * TILE_SIZE + x;

        decodeStrip(byte, tile, TILE_SIZE, idx);
    }
}

fn loadSprites() void {
    for (0..SPRITE_NB) |id| {
        decodeSprite(id);
    }
}

fn decodeSprite(sprite_id: usize) void {
    const SPRITE_BYTES = 64;

    const sprite = &sprites[sprite_id];
    const sprite_addr = sprite_id * SPRITE_BYTES;
    const sprite_data = sprite_rom[sprite_addr .. sprite_addr + SPRITE_BYTES];

    for (sprite_data, 0..) |byte, i| {
        const x: usize, const y: usize = switch (i) {
            0...7 => .{ 15 - i % 8, 15 },
            8...15 => .{ 15 - i % 8, 3 },
            16...23 => .{ 15 - i % 8, 7 },
            24...31 => .{ 15 - i % 8, 11 },
            32...39 => .{ 7 - i % 8, 15 },
            40...47 => .{ 7 - i % 8, 3 },
            48...55 => .{ 7 - i % 8, 7 },
            56...63 => .{ 7 - i % 8, 11 },
            else => unreachable,
        };

        const idx = y * SPRITE_SIZE + x;

        decodeStrip(byte, sprite, SPRITE_SIZE, idx);
    }
}

fn decodeStrip(
    byte: u8,
    buff: []u2,
    size: usize,
    start: usize,
) void {
    const lower_bits: u4 = @truncate(byte & 0x0f);
    const upper_bits: u4 = @truncate(byte >> 4);

    for (0..4) |i| {
        const bit_idx: u2 = @intCast(i);
        const mask: u4 = @as(u4, 0b1) << bit_idx;

        const lsb = (lower_bits & mask) >> bit_idx;
        const msb = (upper_bits & mask) >> bit_idx;

        const pixel: u2 = @truncate((msb << 1) | lsb);

        const idx = start - i * size;

        buff[idx] = pixel;
    }
}

fn renderFrame() void {
    renderTiles();
}

fn renderTiles() void {
    const vram_tile_addr = 0x4000;
    const vram_palette_addr = 0x4400;

    // top and bottom lines
    inline for ([_]enum { top, bottom }{ .top, .bottom }) |v| {
        const row, const start_addr = switch (v) {
            .top => .{ 0, 0x3c2 },
            .bottom => .{ SCREEN_TILE_HEIGHT - 2, 0x002 },
        };

        for (0..SCREEN_TILE_WIDTH) |col| {
            for (0..2) |i| {
                const offset = 0x020 * i;
                const addr = start_addr + SCREEN_TILE_WIDTH - col - 1 + offset;

                const tile_id = memRead(@intCast(vram_tile_addr + addr));
                const palette_id = memRead(@intCast(vram_palette_addr + addr));

                const base_idx = row * SCREEN_WIDTH * TILE_SIZE + col * TILE_SIZE;

                renderTile(tile_id, palette_id, base_idx + (SCREEN_WIDTH * TILE_SIZE * i));
            }
        }
    }

    // game grid
    for (0..SCREEN_TILE_WIDTH) |col| {
        const start_addr = 0x3a0 - 0x020 * col;

        for (2..SCREEN_TILE_HEIGHT - 2) |row| {
            const tile_id = memRead(@intCast(vram_tile_addr + start_addr + (row - 2)));
            const palette_id = memRead(@intCast(vram_palette_addr + start_addr + (row - 2)));

            const base_idx = row * SCREEN_WIDTH * TILE_SIZE + col * TILE_SIZE;

            renderTile(tile_id, palette_id, base_idx);
        }
    }
}

fn renderTile(tile_id: u8, palette_id: u8, base_idx: usize) void {
    const tile = tiles[tile_id];
    const palette = palettes[palette_id & 0x3f];

    for (tile, 0..) |pixel, j| {
        const color_id = palette[pixel];
        const color = colors[color_id];

        const x = j % TILE_SIZE;
        const y = j / TILE_SIZE;

        const idx = (base_idx + y * SCREEN_WIDTH + x) * BYTE_PER_PIXEL;

        frame_buffer[idx + 0] = color.r;
        frame_buffer[idx + 1] = color.g;
        frame_buffer[idx + 2] = color.b;
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
    const buffer = try alloc.alloc(u8, TILE_NB * TILE_NB_PIXEL * BYTE_PER_PIXEL);

    renderMap(buffer, .tile);

    return buffer;
}

pub fn renderSprite(alloc: Allocator) ![]u8 {
    const buffer = try alloc.alloc(u8, SPRITE_NB * SPRITE_NB_PIXEL * BYTE_PER_PIXEL);

    renderMap(buffer, .sprite);

    return buffer;
}

fn renderMap(
    buff: []u8,
    comptime map_type: enum { tile, sprite },
) void {
    const MAP_SIZE = 128;

    const UNIT_SIZE, const UNIT_NB_PIXEL = switch (map_type) {
        .tile => .{ TILE_SIZE, TILE_NB_PIXEL },
        .sprite => .{ SPRITE_SIZE, SPRITE_NB_PIXEL },
    };
    const UNIT_PER_LINE = MAP_SIZE / UNIT_SIZE;

    const palette = palettes[1];

    for (0..UNIT_PER_LINE) |row| {
        for (0..UNIT_PER_LINE) |col| {
            const id = row * UNIT_PER_LINE + col;
            const base_idx = row * UNIT_PER_LINE * UNIT_NB_PIXEL + col * UNIT_SIZE;

            const unit = switch (map_type) {
                .tile => tiles[id],
                .sprite => sprites[id],
            };

            for (unit, 0..) |pixel, i| {
                const color_id = palette[pixel];
                const color = colors[color_id];

                const x = i % UNIT_SIZE;
                const y = i / UNIT_SIZE;

                const idx = (base_idx + y * UNIT_PER_LINE * UNIT_SIZE + x) * BYTE_PER_PIXEL;

                buff[idx + 0] = color.r;
                buff[idx + 1] = color.g;
                buff[idx + 2] = color.b;
            }
        }
    }
}
