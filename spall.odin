package main

import "base:runtime"
import "core:prof/spall"

SPALL_ENABLED :: #config(SPALL_ENABLED, false)

spall_ctx: spall.Context
spall_buffer: spall.Buffer

when SPALL_ENABLED {
    @(instrumentation_enter)
    spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
        spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
    }
    @(instrumentation_exit)
    spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
        spall._buffer_end(&spall_ctx, &spall_buffer)
    }

    spall_init :: proc(filename: string) {
        spall_ctx = spall.context_create(filename)
        buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
        spall_buffer = spall.buffer_create(buffer_backing)
    }
    spall_uninit :: proc() {
        spall.buffer_destroy(&spall_ctx, &spall_buffer)
        spall.context_destroy(&spall_ctx)
    }
} else {
    spall_init :: proc(filename: string) {
        // do nothing
    }
    spall_uninit :: proc() {
        // do nothing
    }
}

