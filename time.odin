#+ build !windows
package main

import "core:time"

sleep :: proc "contextless" (d: time.Duration) {
	time.accurate_sleep(d)
}