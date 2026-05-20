// ********** imports ********** //

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;

const Z80 = @import("zig80");

// ********** constants ********** //

const TILE_SIZE = 8;
const SPRITE_SIZE = 16;

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
}

pub fn runNextFrame() void {
    for (0..CYCLES_PER_FRAMES) |_| {
        cpu.step();
    }
}

pub fn getCycles() u64 {
    return cpu.cycles;
}

pub fn dumpMemory(io: Io) !void {
    const cwd = Dir.cwd();

    try cwd.writeFile(io, .{ .data = &memory, .sub_path = "memory.bin" });
    try cwd.writeFile(io, .{ .data = &sprite_rom, .sub_path = "sprite.bin" });
    try cwd.writeFile(io, .{ .data = &tile_rom, .sub_path = "tile.bin" });
    try cwd.writeFile(io, .{ .data = &color_rom, .sub_path = "color.bin" });
    try cwd.writeFile(io, .{ .data = &palette_rom, .sub_path = "palette.bin" });
}

// ********** private functions ********** //

fn loadRoms(io: Io) !void {
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

                @memcpy(memory[start_addr..end_addr], data);
            },
            4 => @memcpy(tile_rom[0..tile_rom.len], data),
            5 => @memcpy(sprite_rom[0..sprite_rom.len], data),
            6 => @memcpy(color_rom[0..color_rom.len], data),
            7 => @memcpy(palette_rom[0..palette_rom.len], data),
            else => unreachable,
        }
    }
}
