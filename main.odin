package main

import "jo:app"

import "core:fmt"
import "core:log"
import "core:image/png"
import "core:time"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

png_load :: proc($path: string) -> (^png.Image, png.Error) {
	data := #load(path)
	return png.load_from_bytes(data)
}

Entity_Flag :: enum {
	Active,
	Idle,
	Projectile,
	Hostile,
	Flying,
}

Entity_Flags :: distinct bit_set[Entity_Flag]

Entity_ID :: struct {
	// idx: index in entity array
	// gen: generation of entity
	idx, gen: int,
}

Entity :: struct {
	gen: int,
	using pos: [2]f32,
	vel: [2]f32,
	flip: bool,
	tick: f32,
	frame: int,
	flags: Entity_Flags,
	spr: ^png.Image,
}

player_init :: proc(using player: ^Entity, s: ^png.Image) {
	spr = s
	x = f32(GAME_WIDTH/2 - POLAR_BEAR_FRAME_WIDTH/2)
}

player_update :: proc(using player: ^Entity, dt: f32) {
	left_stick: [2]f32
	if app.gamepad_connected(0) {
		left_stick = app.gamepad_left_stick(0)
	} else {
		left_stick.x -= f32(i32(app.key_down(.Left)))
		left_stick.x += f32(i32(app.key_down(.Right)))
		left_stick.y -= f32(i32(app.key_down(.Down)))
		left_stick.y += f32(i32(app.key_down(.Up)))
	}

	DIR_THRESHOLD :: 0.3
	if left_stick.x > DIR_THRESHOLD {
		flip = false
	} else if left_stick.x < -DIR_THRESHOLD {
		flip = true
	}

	if left_stick.x == 0 && .Idle not_in flags {
		flags += {.Idle}
		tick = 0
		frame = 0
	} else if left_stick.x != 0 && .Idle in flags {
		flags -= {.Idle}
		tick = 0
		frame = 0
	}

	entity_anim_update(player, 
		abs(left_stick.x)*dt if left_stick.x != 0.0 else dt, 
		POLAR_BEAR_FRAME_TIME, 
		POLAR_BEAR_FRAME_COUNT_IDLE if .Idle in flags else POLAR_BEAR_FRAME_COUNT_WALK)

	VEL_X :: 10.0

	x += left_stick.x*VEL_X*dt
}

player_draw :: proc(backbuffer: []u32, using player: ^Entity) {
	if .Idle in flags {
		draw_image_cropped(backbuffer, x, y, flip, spr, frame*POLAR_BEAR_FRAME_WIDTH, 0, POLAR_BEAR_FRAME_WIDTH, POLAR_BEAR_FRAME_HEIGHT)
	} else {
		draw_image_cropped(backbuffer, x, y, flip, spr, POLAR_BEAR_FRAME_COUNT_IDLE*POLAR_BEAR_FRAME_WIDTH + frame*POLAR_BEAR_FRAME_WIDTH, 0, POLAR_BEAR_FRAME_WIDTH, POLAR_BEAR_FRAME_HEIGHT)
	}
}

entity_anim_update :: proc(using entity: ^Entity, dt: f32, frame_time: f32, frame_count: int) {
	tick += dt
	if tick > frame_time {
		tick = 0
		frame += 1
		if frame >= frame_count {
			frame = 0
		}
	}
}

Game :: struct {
	spr_polar_bear, spr_explode, spr_flying_cycle, spr_drone: ^png.Image,
	dt: f32,
	player: Entity,
	entities: [MAX_ENTITIES]Entity,
	entity_count: int,
	fireball_count: int,
	backbuffer: []u32,
	drone_spawn_time: f32,
}

create_entity :: proc(using game: ^Game, new_entity: Entity) -> ^Entity {
	assert(entity_count - 1 < MAX_ENTITIES, "Too many entities")
	for &entity, entity_idx in entities {
		if .Active not_in entity.flags {
			new_gen := entity.gen + 1
			entity = new_entity
			entity.gen = new_gen
			entity.flags += {.Active}
			entity_count += 1
			return &entity
		}
	}
	panic("failed to create entity")
}

destroy_entity :: proc(using game: ^Game, entity: ^Entity) {
	entity.flags -= {.Active}
	game.entity_count -= 1
}

entity_active :: proc(using entity: Entity) -> bool {
	return .Active in flags
}

game_reset :: proc(using game: ^Game) {
	player_init(&game.player, game.spr_polar_bear)
	game.drone_spawn_time = 3
	game.entity_count = 0
	game.fireball_count = 0

	mem.set(raw_data(game.entities[:]), 0, len(game.entities) * size_of(Entity))
}

main :: proc() {
	spall_init("spall")
	defer spall_uninit()

	when ODIN_DEBUG {
		when ODIN_OS == .Windows {
			context.logger = create_debug_logger(.Debug, {.Level, .Terminal_Color, .Short_File_Path, .Line, .Procedure})
		} else {
			context.logger = log.create_console_logger(.Debug, {.Level, .Terminal_Color, .Short_File_Path, .Line, .Procedure})
		}
	}

	app.init(title = "Odin Holiday Jam")

	game: Game

	game.backbuffer = make([]u32, GAME_WIDTH * GAME_HEIGHT)

	// https://rapidpunches.itch.io/polar-bear
	game.spr_polar_bear = png_load("sprites/polar_bear.png") or_else panic("Failed to load polar_bear.png")

	// https://msfrantz.itch.io/free-fire-ball-pixel-art
	game.spr_explode = png_load("sprites/explode.png") or_else panic("Failed to load explode.png")
	game.spr_flying_cycle = png_load("sprites/flying_cycle.png") or_else panic("Failed to load flying_cycle.png")

	// made by me
	game.spr_drone = png_load("sprites/drone.png") or_else panic("Failed to load drone.png")

	max_dt := 1.0/f32(app.refresh_rate())
	game.dt = max_dt
	max_dt_dur := time.Second / time.Duration(app.refresh_rate())
	dt_dur := max_dt_dur

	player_init(&game.player, game.spr_polar_bear)

	game.drone_spawn_time = 3

	for app.running() {
		start_tick := time.tick_now()
		defer {
			end_tick := time.tick_now()
			dt_dur = time.tick_diff(start_tick, end_tick)
			if dt_dur < max_dt_dur {
				sleep(max_dt_dur - dt_dur)
				game.dt = max_dt
			} else {
				game.dt = f32(dt_dur)/f32(time.Second)
			}
		}

		mem.set(raw_data(game.backbuffer), 255, size_of(u32) * len(game.backbuffer))
		defer app.swap_buffers(game.backbuffer, GAME_WIDTH, GAME_HEIGHT)

		player_update(&game.player, game.dt)
		player_draw(game.backbuffer, &game.player)

		// spawn fireball
		{
			right_stick: [2]f32
			if app.gamepad_connected(0) {
				right_stick = app.gamepad_right_stick(0)
			} else {
				// mouse_x, mouse_y := app.mouse_position()
				// TODO
			}
			if app.gamepad_button_pressed(0, .Right_Shoulder) && linalg.length(right_stick) > 0.8 && game.fireball_count < 3 {
				fireball := Entity {
					pos = {game.player.x + POLAR_BEAR_FRAME_WIDTH/2 if !game.player.flip else game.player.x - POLAR_BEAR_FRAME_WIDTH/2, game.player.y - 8},
					vel = right_stick * 2, // TODO: Something doesn't feel right about aiming.
					flags = {.Projectile},
				}
				create_entity(&game, fireball)
				game.fireball_count += 1
			}
		}

		// spawn drone
		{
			game.drone_spawn_time -= game.dt
			if game.drone_spawn_time <= 0 {
				game.drone_spawn_time = rand.float32_range(1, 5)
				right := rand.choice([]bool{false, true})
				drone: Entity
				drone.x = 1 if right else GAME_WIDTH - 1
				drone.y = rand.float32_range(GAME_HEIGHT - DRONE_FRAME_HEIGHT*2, GAME_HEIGHT - DRONE_FRAME_HEIGHT)
				drone.vel.x = rand.float32_range(0.1, 1)
				if !right {
					drone.vel.x = -drone.vel.x
				}
				drone.tick = 1
				drone.flags = {.Hostile, .Flying}
				create_entity(&game, drone)
			}
		}

		game_loop: for &entity, entity_idx in game.entities {
			if entity_idx >= game.entity_count {
				break
			}

			using entity
			if .Active in flags {
				pos += vel

				if .Projectile in flags && .Hostile not_in flags {
					entity_anim_update(&entity, game.dt, FLYING_CYCLE_FRAME_TIME, FLYING_CYCLE_FRAME_COUNT_LOOP)
					if (y-FLYING_CYCLE_FRAME_HEIGHT > GAME_HEIGHT) || (x+FLYING_CYCLE_FRAME_WIDTH < 0) || (x-FLYING_CYCLE_FRAME_WIDTH > GAME_WIDTH) {
						destroy_entity(&game, &entity)
						game.fireball_count -= 1
					} else {
						draw_image_cropped(game.backbuffer, x, y, false, game.spr_flying_cycle, FLYING_CYCLE_FRAME_COUNT_START*FLYING_CYCLE_FRAME_WIDTH + frame*FLYING_CYCLE_FRAME_WIDTH, 0, FLYING_CYCLE_FRAME_WIDTH, FLYING_CYCLE_FRAME_HEIGHT)
					}
				}
				else if .Hostile in flags && .Flying in flags {
					if (x+DRONE_FRAME_WIDTH < 0) || (x-DRONE_FRAME_WIDTH > GAME_WIDTH) {
						destroy_entity(&game, &entity)
					} else {
						tick -= game.dt
						if tick <= 0 {
							tick = 1
							laser: Entity
							laser.pos = pos
							laser.y -= 5
							laser.vel.y = -0.5
							laser.flags = {.Projectile, .Hostile}
							create_entity(&game, laser)
							laser.x = pos.x + 20
							create_entity(&game, laser)
						}
						draw_image(game.backbuffer, x, y, false, game.spr_drone)
					}
				}
				else if .Projectile in flags && .Hostile in flags {
					if y + LASER_HEIGHT < 0 {
						destroy_entity(&game, &entity)
					} else {
						if collision_recs(x, y, LASER_WIDTH, LASER_HEIGHT, game.player.x, game.player.y, POLAR_BEAR_FRAME_WIDTH, POLAR_BEAR_FRAME_HEIGHT) {
							game_reset(&game)
							break game_loop
						}

						draw_rectangle(game.backbuffer, x, y, LASER_WIDTH, LASER_HEIGHT, 0x00FF0000)
					}
				}
			}
		}

		fireball_loop: for &fireball, fireball_idx in game.entities {
			if fireball_idx >= game.entity_count {
				break
			}
			if !entity_active(fireball) {
				continue
			}

			if .Projectile in fireball.flags && .Hostile not_in fireball.flags {
				for &entity, entity_idx in game.entities {
					if entity_idx >= game.entity_count {
						break
					}
					if !entity_active(entity) {
						continue
					}

					if .Hostile in entity.flags {
						if .Projectile in entity.flags {
							if collision_recs(fireball.x+FLYING_CYCLE_FRAME_WIDTH/2, fireball.y+FLYING_CYCLE_FRAME_HEIGHT/2, FLYING_CYCLE_FRAME_WIDTH/2, FLYING_CYCLE_FRAME_HEIGHT/2, entity.x, entity.y, LASER_WIDTH, LASER_HEIGHT) {
								destroy_entity(&game, &fireball)
								destroy_entity(&game, &entity)
								game.fireball_count -= 1
								continue fireball_loop
							}
						} else {
							if collision_recs(fireball.x+FLYING_CYCLE_FRAME_WIDTH/2, fireball.y+FLYING_CYCLE_FRAME_HEIGHT/2, FLYING_CYCLE_FRAME_WIDTH/2, FLYING_CYCLE_FRAME_HEIGHT/2, entity.x, entity.y, DRONE_FRAME_WIDTH, DRONE_FRAME_HEIGHT) {
								destroy_entity(&game, &fireball)
								destroy_entity(&game, &entity)
								game.fireball_count -= 1
								continue fireball_loop
							}
						}
					}
				}
			}
		}
	}
}

collision_recs :: #force_inline proc "contextless" (x0, y0, w0, h0, x1, y1, w1, h1: f32) -> bool {
	return x0+w0 >= x1 && x0 <= x1 + w1 && y0 + w0 >= y1 && y0 <= y1 + h1
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