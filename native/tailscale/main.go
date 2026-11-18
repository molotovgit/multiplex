// Package main builds libmpxtailscale: Tailscale inside Multiplex.
//
// It runs a Tailscale node in the app's own process (tsnet, userspace
// networking), so the phone joins the user's tailnet without the
// Tailscale VPN app. The Rust core loads this library at run time and
// calls the C functions below; a connection to a tailnet device comes
// back as a plain socket file descriptor that russh reads and writes
// like any TCP connection.
//
// Build: ./build-android.sh (see there). Everything here is safe to call
// from any thread.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	// Makes netmon, DNS and TLS roots work for an app UID on Android,
	// which may not list network interfaces or read /proc/net.
	_ "tailscale.com/feature/androidbin"
	"tailscale.com/ipn"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
)

var (
	mu      sync.Mutex
	srv     *tsnet.Server
	lastErr string
	logFile *os.File
)

func fail(err error) C.int {
	mu.Lock()
	lastErr = err.Error()
	mu.Unlock()
	return -1
}

func cstr(s string) *C.char { return C.CString(s) }

// mpx_ts_start starts the node with its state in dir (kept across runs,
// so the user signs in once). Calling it again while running does nothing.
//
//export mpx_ts_start
func mpx_ts_start(dir, hostname *C.char) C.int {
	mu.Lock()
	defer mu.Unlock()
	if srv != nil {
		return 0
	}
	d := C.GoString(dir)
	if err := os.MkdirAll(d, 0o700); err != nil {
		lastErr = err.Error()
		return -1
	}
	// Tailscale's own diagnostics stay on the phone, in one small file.
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true")
	// Android has no standard place for Tailscale's log state; without
	// this it gives up ("no safe place found to store log state").
	os.Setenv("TS_LOGS_DIR", d)
	logPath := filepath.Join(d, "tailscale.log")
	if fi, err := os.Stat(logPath); err == nil && fi.Size() > 4<<20 {
		os.Remove(logPath)
	}
	f, _ := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	logFile = f
	logf := func(format string, args ...any) {
		if logFile != nil {
			fmt.Fprintf(logFile, time.Now().Format("15:04:05.000 ")+format+"\n", args...)
		}
	}
	s := &tsnet.Server{
		Dir:      d,
		Hostname: C.GoString(hostname),
		Logf:     logf,
		UserLogf: logf,
	}
	if err := s.Start(); err != nil {
		lastErr = err.Error()
		return -1
	}
	srv = s
	return 0
}

func client() (*tsnet.Server, error) {
	mu.Lock()
	defer mu.Unlock()
	if srv == nil {
		return nil, errors.New("Tailscale is not started")
	}
	return srv, nil
}

type peer struct {
	Name    string   `json:"name"`
	DNSName string   `json:"dnsName"`
	IPs     []string `json:"ips"`
	OS      string   `json:"os"`
	Online  bool     `json:"online"`
	Self    bool     `json:"self"`
	// Direct: a peer-to-peer path is in use (fastest). Otherwise traffic
	// goes through Tailscale's relay in Relay (a region code like "fra").
	Direct bool   `json:"direct"`
	Relay  string `json:"relay"`
}

type status struct {
	// NoState, NeedsLogin, NeedsMachineAuth, Stopped, Starting, Running.
	State   string `json:"state"`
	AuthURL string `json:"authUrl"`
	Tailnet string `json:"tailnet"`
	User    string `json:"user"`
	Self    *peer  `json:"self"`
	Peers   []peer `json:"peers"`
	Error   string `json:"error"`
}

// mpx_ts_status returns the node's state and devices as JSON. Free the
// result with mpx_ts_free.
//
//export mpx_ts_status
func mpx_ts_status() *C.char {
	out := status{State: "NoState"}
	s, err := client()
	if err != nil {
		out.Error = err.Error()
		return jsonC(out)
	}
	lc, err := s.LocalClient()
	if err != nil {
		out.Error = err.Error()
		return jsonC(out)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := lc.Status(ctx)
	if err != nil {
		out.Error = err.Error()
		return jsonC(out)
	}
	out.State = st.BackendState
	out.AuthURL = st.AuthURL
	if st.CurrentTailnet != nil {
		out.Tailnet = st.CurrentTailnet.Name
	}
	if st.Self != nil {
		me := toPeer(st.Self.HostName, st.Self.DNSName, st.Self.TailscaleIPs, st.Self.OS, true)
		me.Self = true
		out.Self = &me
		if u, ok := st.User[st.Self.UserID]; ok {
			out.User = u.LoginName
		}
	}
	for _, p := range st.Peer {
		pp := toPeer(p.HostName, p.DNSName, p.TailscaleIPs, p.OS, p.Online)
		pp.Direct = p.CurAddr != ""
		pp.Relay = p.Relay
		out.Peers = append(out.Peers, pp)
	}
	mu.Lock()
	out.Error = lastErr
	mu.Unlock()
	return jsonC(out)
}

func toPeer[T fmt.Stringer](host, dns string, ips []T, os string, online bool) peer {
	p := peer{Name: host, DNSName: strings.TrimSuffix(dns, "."), OS: os, Online: online}
	for _, ip := range ips {
		p.IPs = append(p.IPs, ip.String())
	}
	return p
}

func jsonC(v any) *C.char {
	b, _ := json.Marshal(v)
	return cstr(string(b))
}

// mpx_ts_login starts an interactive sign-in; the sign-in page then shows
// up as authUrl in mpx_ts_status.
//
//export mpx_ts_login
func mpx_ts_login() C.int {
	s, err := client()
	if err != nil {
		return fail(err)
	}
	lc, err := s.LocalClient()
	if err != nil {
		return fail(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	// Make sure the node wants to run, then ask for a sign-in page.
	_, _ = lc.EditPrefs(ctx, &ipn.MaskedPrefs{Prefs: ipn.Prefs{WantRunning: true}, WantRunningSet: true})
	if err := lc.StartLoginInteractive(ctx); err != nil {
		return fail(err)
	}
	return 0
}

// mpx_ts_logout signs this phone out of the tailnet.
//
//export mpx_ts_logout
func mpx_ts_logout() C.int {
	s, err := client()
	if err != nil {
		return fail(err)
	}
	lc, err := s.LocalClient()
	if err != nil {
		return fail(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := lc.Logout(ctx); err != nil {
		return fail(err)
	}
	return 0
}

// mpx_ts_dial connects to host:port on the tailnet (a device name such as
// "omarchy", its full MagicDNS name or a 100.x address) and returns a
// socket file descriptor carrying the connection, or -1 (see
// mpx_ts_last_error). The caller owns the descriptor and closes it.
//
//export mpx_ts_dial
func mpx_ts_dial(host *C.char, port C.int, timeoutMs C.int) C.int {
	s, err := client()
	if err != nil {
		return fail(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()
	addr := net.JoinHostPort(C.GoString(host), strconv.Itoa(int(port)))
	remote, err := s.Dial(ctx, "tcp", addr)
	if err != nil {
		return fail(fmt.Errorf("could not reach %s over Tailscale: %w", addr, err))
	}
	// One end of a local socket pair goes to Rust; the other is pumped to
	// and from the tailnet connection.
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		remote.Close()
		return fail(err)
	}
	f := os.NewFile(uintptr(fds[0]), "tailscale-pipe")
	local, err := net.FileConn(f)
	f.Close()
	if err != nil {
		remote.Close()
		syscall.Close(fds[1])
		return fail(err)
	}
	go pump(local, remote)
	return C.int(fds[1])
}

// pump copies both ways and passes each side's end on to the other.
func pump(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if c, ok := dst.(interface{ CloseWrite() error }); ok {
			c.CloseWrite()
		} else {
			dst.Close()
		}
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
	<-done
	a.Close()
	b.Close()
}

// mpx_ts_ping pings a tailnet address and returns the round trip in
// milliseconds, or a negative number. kind is "disco" (the network path
// only), "TSMP" (through WireGuard and the IP stacks, no TCP) or "ICMP".
// For diagnosing where delay comes from.
//
//export mpx_ts_ping
func mpx_ts_ping(ip *C.char, kind *C.char) C.double {
	s, err := client()
	if err != nil {
		return -1
	}
	lc, err := s.LocalClient()
	if err != nil {
		return -1
	}
	addr, err := netip.ParseAddr(C.GoString(ip))
	if err != nil {
		return -2
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	res, err := lc.Ping(ctx, addr, tailcfg.PingType(C.GoString(kind)))
	if err != nil || res.Err != "" {
		return -3
	}
	return C.double(res.LatencySeconds * 1000)
}

// mpx_ts_last_error returns the last error message. Free with mpx_ts_free.
//
//export mpx_ts_last_error
func mpx_ts_last_error() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return cstr(lastErr)
}

//export mpx_ts_free
func mpx_ts_free(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
