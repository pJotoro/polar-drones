package main

import "jo:app"

import "core:fmt"
import "core:image/png"
import "core:time"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"

GAME_WIDTH :: 384
GAME_HEIGHT :: 216

png_load :: proc($path: string) -> (^png.Image, png.Error) {
	data := #load(path)
	return png.load_from_bytes(data)
}

main :: proc() {
	spall_init("spall")
	defer spall_uninit()

	when ODIN_OS == .Windows {
		context.logger = create_debug_logger(.Warning, {.Level, .Terminal_Color, .Short_File_Path, .Line, .Procedure})
	}

	app.init(title = "Odin Holiday Jam")

	backbuffer := make([]u32, GAME_WIDTH * GAME_HEIGHT)

	// https://rapidpunches.itch.io/polar-bear
	polar_bear, err := png_load("sprites/polar_bear.png")
	POLAR_BEAR_FRAME_WIDTH :: 32
	POLAR_BEAR_FRAME_HEIGHT :: 32
	POLAR_BEAR_FRAME_TIME :: 0.25
	POLAR_BEAR_IDLE_FRAME_COUNT :: 3
	POLAR_BEAR_WALK_FRAME_COUNT :: 4

	max_dt := 1.0/f32(app.refresh_rate())
	dt := max_dt
	max_dt_dur := time.Second / time.Duration(app.refresh_rate())
	dt_dur := max_dt_dur

	tick: f32
	frame: int

	for app.running() {
		start_tick := time.tick_now()
		defer {
			end_tick := time.tick_now()
			dt_dur = time.tick_diff(start_tick, end_tick)
			if dt_dur < max_dt_dur {
				sleep(max_dt_dur - dt_dur)
				dt = max_dt
			} else {
				dt = f32(dt_dur)/f32(time.Second)
			}
		}

		mem.set(raw_data(backbuffer), 255, size_of(u32) * len(backbuffer))
		defer app.swap_buffers(backbuffer, GAME_WIDTH, GAME_HEIGHT)

		tick += dt
		if tick > POLAR_BEAR_FRAME_TIME {
			tick = 0
			frame += 1
			if frame >= POLAR_BEAR_WALK_FRAME_COUNT {
				frame = 0
			}
		}
		draw_image_cropped(backbuffer, 50, 50, false, polar_bear, POLAR_BEAR_IDLE_FRAME_COUNT*POLAR_BEAR_FRAME_WIDTH + frame*POLAR_BEAR_FRAME_WIDTH, 0, POLAR_BEAR_FRAME_WIDTH, POLAR_BEAR_FRAME_HEIGHT)
	}
}

draw_rectangle_int :: proc(backbuffer: []u32, x, y, width, height: int, color: u32) {
	for ypos in max(y, 0)..<min(y+height, GAME_HEIGHT) {
		for xpos in max(x, 0)..<min(x+width, GAME_WIDTH) {
			backbuffer[GAME_WIDTH*ypos + xpos] = color
		}
	}
}

draw_rectangle_f32 :: proc(backbuffer: []u32, x, y: f32, width, height: int, color: u32) {
	draw_rectangle_int(backbuffer, int(math.floor(x)), int(math.floor(y)), width, height, color)
}

draw_rectangle :: proc {
	draw_rectangle_int,
	draw_rectangle_f32,
}

draw_image_int :: proc(backbuffer: []u32, x, y: int, hflip: bool, img: ^png.Image) {
	if x + img.width < 0 || x >= app.width() || y + img.height < 0 || y >= app.height() {
		return
	}

	img_buf := slice.reinterpret([]u32, img.pixels.buf[:])

	if !hflip {
		img_y := 0
		if y+img.height >= GAME_HEIGHT {
			img_y += (y+img.height - GAME_HEIGHT)
		}
		for ypos := min(y+img.height, GAME_HEIGHT) - 1; ypos >= max(y, 0); ypos -= 1 {
			img_x := 0
			if x < 0 {
				img_x -= x
			}
			for xpos in max(x, 0)..<min(x+img.width, GAME_WIDTH) {
				pixel := img_buf[img.width*img_y + img_x]
				if pixel != 0 {
					pixel_bytes := transmute([4]byte)pixel
					pixel_bytes = pixel_bytes.bgra
					pixel = transmute(u32)pixel_bytes
					backbuffer[GAME_WIDTH*ypos + xpos] = pixel
				}
				img_x += 1
			}
			img_y += 1
		}
	} else {
		img_y := 0
		if y+img.height >= GAME_HEIGHT {
			img_y += (y+img.height - GAME_HEIGHT)
		}
		for ypos := min(y+img.height, GAME_HEIGHT) - 1; ypos >= max(y, 0); ypos -= 1 {
			img_x := 0
			if x+img.width >= GAME_WIDTH {
				img_x += (x+img.width - GAME_WIDTH)
			}
			for xpos := min(x+img.width, GAME_WIDTH) - 1; xpos >= max(x, 0); xpos -= 1 {
				pixel := img_buf[img.width*img_y + img_x]
				if pixel != 0 {
					pixel_bytes := transmute([4]byte)pixel
					pixel_bytes = pixel_bytes.bgra
					pixel = transmute(u32)pixel_bytes
					backbuffer[GAME_WIDTH*ypos + xpos] = pixel
				}
				img_x += 1
			}
			img_y += 1
		}
	}
}

draw_image_f32 :: proc(backbuffer: []u32, x, y: f32, hflip: bool, img: ^png.Image) {
	draw_image_int(backbuffer, int(math.floor(x)), int(math.floor(y)), hflip, img)
}

draw_image :: proc {
	draw_image_int,
	draw_image_f32,
}

draw_image_cropped_int :: proc(backbuffer: []u32, x, y: int, hflip: bool, img: ^png.Image, crop_x, crop_y, crop_width, crop_height: int) {
	if x + crop_width < 0 || x >= app.width() || y + crop_height < 0 || y >= app.height() {
		return
	}

	img_buf := slice.reinterpret([]u32, img.pixels.buf[:])

	if !hflip {
		img_y := crop_y
		if y+crop_height >= GAME_HEIGHT {
			img_y += (y+crop_height - GAME_HEIGHT)
		}
		for ypos := min(y+crop_height, GAME_HEIGHT) - 1; ypos >= max(y, 0); ypos -= 1 {
			img_x := crop_x
			if x < 0 {
				img_x -= x
			}
			for xpos in max(x, 0)..<min(x+crop_width, GAME_WIDTH) {
				pixel := img_buf[img.width*img_y + img_x]
				if pixel != 0 {
					pixel_bytes := transmute([4]byte)pixel
					pixel_bytes = pixel_bytes.bgra
					pixel = transmute(u32)pixel_bytes
					backbuffer[GAME_WIDTH*ypos + xpos] = pixel
				}
				img_x += 1
			}
			img_y += 1
		}
	} else {
		img_y := crop_y
		if y+crop_height >= GAME_HEIGHT {
			img_y += (y+crop_height - GAME_HEIGHT)
		}
		for ypos := min(y+crop_height, GAME_HEIGHT) - 1; ypos >= max(y, 0); ypos -= 1 {
			img_x := crop_x
			if x+crop_width >= GAME_WIDTH {
				img_x += (x+crop_width - GAME_WIDTH)
			}
			for xpos := min(x+crop_width, GAME_WIDTH) - 1; xpos >= max(x, 0); xpos -= 1 {
				pixel := img_buf[img.width*img_y + img_x]
				if pixel != 0 {
					pixel_bytes := transmute([4]byte)pixel
					pixel_bytes = pixel_bytes.bgra
					pixel = transmute(u32)pixel_bytes
					backbuffer[GAME_WIDTH*ypos + xpos] = pixel
				}
				img_x += 1
			}
			img_y += 1
		}
	}
}

draw_image_cropped_f32 :: proc(backbuffer: []u32, x, y: f32, hflip: bool, img: ^png.Image, crop_x, crop_y, crop_width, crop_height: int) {
	draw_image_cropped_int(backbuffer, int(math.floor(x)), int(math.floor(y)), hflip, img, crop_x, crop_y, crop_width, crop_height)
}

draw_image_cropped :: proc {
	draw_image_cropped_int,
	draw_image_cropped_f32,
}

vclamp :: #force_inline proc(v: [2]f32, value: f32) -> [2]f32 {
    if (value < 0.001) {
        return {0.0, 0.0}
    }

    v_sq := linalg.length2(v)
    if (v_sq > value * value) {
        scale := value * linalg.inverse_sqrt(v_sq)
        return v * scale
    }

    return v
}