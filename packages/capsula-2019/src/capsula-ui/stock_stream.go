// SPDX-License-Identifier: MIT
package main

import (
	"bufio"
	"context"
	"os/exec"
	"time"
)

// Follow only new stock messages, in order. Never log their contents: the stock
// journal contains credentials. One bounded scanner replaces repeated snapshots.
func followStock(ctx context.Context, consume func(string)) {
	for ctx.Err() == nil {
		cmd := exec.CommandContext(ctx, "logread", "-f")
		out, err := cmd.StdoutPipe()
		if err != nil {
			return
		}
		if err = cmd.Start(); err != nil {
			return
		}
		scan := bufio.NewScanner(out)
		scan.Buffer(make([]byte, 4096), 65536)
		for scan.Scan() {
			consume(scan.Text())
		}
		if ctx.Err() == nil && cmd.Process != nil {
			cmd.Process.Kill()
		}
		cmd.Wait()
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}
