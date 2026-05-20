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

// ********** public functions ********** //

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    try pacman.init(io);
    try pacman.dumpMemory(io);

    rl.initWindow(SCREEN_WIDTH * SCALE, SCREEN_HEIGHT * SCALE, "pac-man");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    render_texture = try rl.loadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
    defer render_texture.unload();

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
    }

    { // render texture to screen SCALE:1
        rl.beginDrawing();
        defer rl.endDrawing();

        const texture = render_texture.texture;

        const src: rl.Rectangle = .init(
            0,
            0,
            SCREEN_WIDTH,
            SCREEN_HEIGHT,
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
