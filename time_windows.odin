package main

import win32 "core:sys/windows"
import "core:time"

sleep :: proc "contextless" (d: time.Duration) {
	win32.timeBeginPeriod(1)
	time.accurate_sleep(d)
	win32.timeEndPeriod(1)
}