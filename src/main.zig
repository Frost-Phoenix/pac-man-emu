// ********** imports ********** //

const std = @import("std");

const rl = @import("raylib");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const pacman = @import("pacman.zig");

const SCREEN_WIDTH = pacman.SCREEN_WIDTH;
const SCREEN_HEIGHT = pacman.SCREEN_HEIGHT;

// ********** constants ********** //

const SCALE = 3;

// ********** global vars ********** //

var render_texture: rl.RenderTexture2D = undefined;
var tile_test: rl.Texture2D = undefined;

// ********** public functions ********** //

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    try pacman.init(io);
    try pacman.dumpMemory(io);

    rl.initWindow(SCREEN_WIDTH * SCALE, SCREEN_HEIGHT * SCALE, "pac-man");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rl.setTraceLogLevel(.all);

    render_texture = try rl.loadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
    defer render_texture.unload();

    const tile_map = try pacman.renderTileMap(alloc);
    defer alloc.free(tile_map);

    const img: rl.Image = .{
        .data = tile_map.ptr,
        .width = 128,
        .height = 128,
        .format = .uncompressed_r8g8b8,
        .mipmaps = 1,
    };
    tile_test = try rl.loadTextureFromImage(img);
    defer tile_test.unload();

    while (!rl.windowShouldClose()) {
        update();
        render();
    }
}

// ********** private functions ********** //

fn update() void {
    pacman.runNextFrame();
}
fn render() void {
    { // render game to texture 1:1
        render_texture.begin();
        defer render_texture.end();

        rl.clearBackground(.light_gray);

        rl.drawTexture(tile_test, 0, 0, .white);
    }

    { // render texture to screen SCALE:1
        rl.beginDrawing();
        defer rl.endDrawing();

        const texture = render_texture.texture;

        const src: rl.Rectangle = .init(
            0,
            0,
            SCREEN_WIDTH,
            -SCREEN_HEIGHT,
        );
        const dest: rl.Rectangle = .init(
            0,
            0,
            SCREEN_WIDTH * SCALE,
            SCREEN_HEIGHT * SCALE,
        );

        rl.drawTexturePro(texture, src, dest, .init(0, 0), 0, .white);
    }
}
